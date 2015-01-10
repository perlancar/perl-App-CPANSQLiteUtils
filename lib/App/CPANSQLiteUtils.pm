package App::CPANSQLiteUtils;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::Any '$log';

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
                       list_local_cpan_packages
                       list_local_cpan_modules
                       list_local_cpan_dists
                       list_local_cpan_authors
                       list_local_cpan_deps
                       list_local_cpan_rev_deps
               );

sub _connect_db {
    require DBI;

    my %args = @_;

    my $cpan    = $args{cpan};
    my $db_dir  = $args{db_dir} // $cpan;
    my $db_name = $args{db_name} // 'cpandb.sql';

    my $db_path = "$db_dir/$db_name";
    $log->tracef("Connecting to SQLite database at %s ...", $db_path);
    DBI->connect("dbi:SQLite:dbname=$db_path", undef, undef,
                 {RaiseError=>1});
}

sub _complete_mod {
    my %args = @_;

    my $word = $args{word} // '';

    # only run under pericmd
    my $cmdline = $args{cmdline} or return undef;
    my $r = $args{r};

    # force read config file, because by default it is turned off when in
    # completion
    $r->{read_config} = 1;
    my $res = $cmdline->parse_argv($r);

    my $dbh;
    eval { $dbh = _connect_db(%{$res->[2]}) };

    # if we can't connect (probably because --cpan is not set yet), bail
    if ($@) {
        $log->tracef("[comp] can't connect to db, bailing: %s", $@);
        return undef;
    }

    my $sth = $dbh->prepare(
        "SELECT mod_name FROM mods WHERE mod_name LIKE ? ORDER BY mod_name");
    $sth->execute($word . '%');

    # XXX follow Complete::OPT_CI

    my @res;
    while (my ($mod) = $sth->fetchrow_array) {
        # only complete one level deeper at a time
        if ($mod =~ /:\z/) {
            next unless $mod =~ /\A\Q$word\E:*\w+\z/i;
        } else {
            next unless $mod =~ /\A\Q$word\E\w*(::\w+)?\z/i;
        }
        push @res, $mod;
    }

    \@res;
};

sub _complete_dist {
    my %args = @_;

    my $word = $args{word} // '';

    # only run under pericmd
    my $cmdline = $args{cmdline} or return undef;
    my $r = $args{r};

    # force read config file, because by default it is turned off when in
    # completion
    $r->{read_config} = 1;
    my $res = $cmdline->parse_argv($r);

    my $dbh;
    eval { $dbh = _connect_db(%{$res->[2]}) };

    # if we can't connect (probably because --cpan is not set yet), bail
    if ($@) {
        $log->tracef("[comp] can't connect to db, bailing: %s", $@);
        return undef;
    }

    my $sth = $dbh->prepare(
        "SELECT dist_name FROM dists WHERE dist_name LIKE ? ORDER BY dist_name");
    $sth->execute($word . '%');

    # XXX follow Complete::OPT_CI

    my @res;
    while (my ($dist) = $sth->fetchrow_array) {
        # only complete one level deeper at a time
        #if ($dist =~ /-\z/) {
        #    next unless $dist =~ /\A\Q$word\E-*\w+\z/i;
        #} else {
        #    next unless $dist =~ /\A\Q$word\E\w*(-\w+)?\z/i;
        #}
        push @res, $dist;
    }

    \@res;
};

sub _complete_cpanid {
    my %args = @_;

    my $word = $args{word} // '';

    # only run under pericmd
    my $cmdline = $args{cmdline} or return undef;
    my $r = $args{r};

    # force read config file, because by default it is turned off when in
    # completion
    $r->{read_config} = 1;
    my $res = $cmdline->parse_argv($r);

    my $dbh;
    eval { $dbh = _connect_db(%{$res->[2]}) };

    # if we can't connect (probably because --cpan is not set yet), bail
    if ($@) {
        $log->tracef("[comp] can't connect to db, bailing: %s", $@);
        return undef;
    }

    my $sth = $dbh->prepare(
        "SELECT cpanid FROM auths WHERE cpanid LIKE ? ORDER BY cpanid");
    $sth->execute($word . '%');

    # XXX follow Complete::OPT_CI

    my @res;
    while (my ($cpanid) = $sth->fetchrow_array) {
        push @res, $cpanid;
    }

    \@res;
};

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => 'Some utilities that query local CPAN::SQLite database',
};

# XXX actually we only need the database
my %common_args = (
    cpan => {
        summary => 'Path to your local CPAN directory',
        schema  => 'str*',
        description => <<'_',

The CPAN home directory must contain `cpandb.sql`.

_
    },
);

my %query_args = (
    query => {
        summary => 'Search query',
        schema => 'str*',
        cmdline_aliases => {q=>{}},
        pos => 0,
    },
    detail => {
        schema => 'bool',
    },
);

$SPEC{list_local_cpan_authors} = {
    v => 1.1,
    summary => 'List authors in local CPAN::SQLite database',
    args => {
        %common_args,
        %query_args,
    },
    result_naked => 1,
    result => {
        description => <<'_',

By default will return an array of CPAN ID's. If you set `detail` to true, will
return array of records.

_
    },
    examples => [
        {
            summary => 'List all authors',
            argv    => [],
            test    => 0,
        },
        {
            summary => 'Find CPAN IDs which start with something',
            argv    => ['--cpan', '/cpan', 'MICHAEL%'],
            result  => ['MICHAEL', 'MICHAELW'],
            test    => 0,
        },
    ],
};
# XXX filter cpanid
sub list_local_cpan_authors {
    my %args = @_;

    my $detail = $args{detail};
    my $q = $args{query} // ''; # sqlite is case-insensitive by default, yay
    $q = '%'.$q.'%' unless $q =~ /%/;

    my $dbh = _connect_db(%args);

    my @bind;
    my @where;
    if (length($q)) {
        push @where, "(cpanid LIKE ? OR fullname LIKE ? OR email like ?)";
        push @bind, $q, $q, $q;
    }
    my $sql = "SELECT
  cpanid id,
  fullname name,
  email
FROM auths".
        (@where ? " WHERE ".join(" AND ", @where) : "").
            " ORDER BY id";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@bind);
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $detail ? $row : $row->{id};
    }
    \@res;
}

$SPEC{list_local_cpan_packages} = {
    v => 1.1,
    summary => 'List packages in locale CPAN::SQLite database',
    args => {
        %common_args,
        %query_args,
        author => {
            summary => 'Filter by author',
            schema => 'str*',
            cmdline_aliases => {a=>{}},
        },
        dist => {
            summary => 'Filter by distribution',
            schema => 'str*',
            cmdline_aliases => {d=>{}},
        },
    },
    result_naked => 1,
    result => {
        description => <<'_',

By default will return an array of package names. If you set `detail` to true,
will return array of records.

_
    },
};
sub list_local_cpan_packages {
    my %args = @_;

    my $detail = $args{detail};
    my $q = $args{query} // ''; # sqlite is case-insensitive by default, yay
    $q = '%'.$q.'%' unless $q =~ /%/;

    my $dbh = _connect_db(%args);

    my @bind;
    my @where;
    if (length($q)) {
        push @where, "(mod_name LIKE ?)";
        push @bind, $q;
    }
    if ($args{author}) {
        #push @where, "(dist_id IN (SELECT dist_id FROM dists WHERE auth_id IN (SELECT auth_id FROM auths WHERE cpanid=?)))";
        push @where, "(author=?)";
        push @bind, $args{author};
    }
    if ($args{dist}) {
        #push @where, "(dist_id=(SELECT dist_id FROM dists WHERE dist_name=?))";
        push @where, "(dist=?)";
        push @bind, $args{dist};
    }
    my $sql = "SELECT
  mod_name name,
  mod_vers version,
  (SELECT dist_name FROM dists WHERE dist_id=mods.dist_id) dist,
  (SELECT cpanid FROM auths WHERE auth_id=(SELECT auth_id FROM dists WHERE dist_id=mods.dist_id)) author
FROM mods".
        (@where ? " WHERE ".join(" AND ", @where) : "").
            " ORDER BY name";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@bind);
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $detail ? $row : $row->{name};
    }
    \@res;
}

$SPEC{list_local_cpan_modules} = $SPEC{list_local_cpan_packages};
sub list_local_cpan_modules {
    goto &list_local_cpan_packages;
}

$SPEC{list_local_cpan_dists} = {
    v => 1.1,
    summary => 'List distributions in local CPAN::SQLite database',
    args => {
        %common_args,
        %query_args,
        author => {
            summary => 'Filter by author',
            schema => 'str*',
            cmdline_aliases => {a=>{}},
        },
    },
    result_naked => 1,
    result => {
        description => <<'_',

By default will return an array of distribution names. If you set `detail` to
true, will return array of records.

_
    },
    examples => [
        {
            summary => 'List all distributions',
            argv    => ['--cpan', '/cpan'],
            test    => 0,
        },
        {
            summary => 'Grep by distribution name, return detailed record',
            argv    => ['--cpan', '/cpan', 'data-table'],
            test    => 0,
        },
        {
            summary   => 'Filter by author, return JSON',
            src       => 'list-local-cpan-dists --cpan /cpan --author perlancar --json',
            src_plang => 'bash',
            test      => 0,
        },
    ],
};
sub list_local_cpan_dists {
    my %args = @_;

    my $detail = $args{detail};
    my $q = $args{query} // '';
    $q = '%'.$q.'%' unless $q =~ /%/;

    my $dbh = _connect_db(%args);

    my @bind;
    my @where;
    if (length($q)) {
        push @where, "(name LIKE ?)";
        push @bind, $q;
    }
    if ($args{author}) {
        #push @where, "(dist_id IN (SELECT dist_id FROM dists WHERE auth_id IN (SELECT auth_id FROM auths WHERE cpanid=?)))";
        push @where, "(author=?)";
        push @bind, $args{author};
    }
    my $sql = "SELECT
  dist_name name,
  dist_vers version,
  dist_file file,
  (SELECT cpanid FROM auths WHERE auth_id=dists.auth_id) author
FROM dists".
        (@where ? " WHERE ".join(" AND ", @where) : "").
            " ORDER BY name";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@bind);
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $detail ? $row : $row->{name};
    }
    \@res;
}

sub _get_prereqs {
    require Module::CoreList;
    require Version::Util;

    my ($mod, $dbh, $memory, $level, $max_level, $phase, $rel, $include_core, $plver) = @_;

    $log->tracef("Finding dependencies for module %s (level=%i) ...", $mod, $level);

    # first find out which distribution that module belongs to
    my $sth = $dbh->prepare("SELECT dist_id FROM mods WHERE mod_name=?");
    $sth->execute($mod);
    my $modrec = $sth->fetchrow_hashref;
    return [404, "No such module: $mod"] unless $modrec;

    # fetch the dependency information
    $sth = $dbh->prepare("SELECT
  CASE WHEN dp.mod_id THEN (SELECT mod_name FROM mods WHERE mod_id=dp.mod_id) ELSE dp.mod_name END AS module,
  phase,
  rel,
  version
FROM deps dp
WHERE dp.dist_id=?
ORDER BY module");
    $sth->execute($modrec->{dist_id});
    my @res;
    while (my $row = $sth->fetchrow_hashref) {
        next unless $phase eq 'ALL' || $row->{phase} eq $phase;
        next unless $rel   eq 'ALL' || $row->{rel}   eq $rel;
        #say "include_core=$include_core, is_core($row->{module}, $row->{version}, $plver)=", Module::CoreList::is_core($row->{module}, $row->{version}, version->parse($plver)->numify);
        next if !$include_core && Module::CoreList::is_core($row->{module}, $row->{version}, version->parse($plver)->numify);
        if (defined $memory->{$row->{module}}) {
            if (Version::Util::version_gt($row->{version}, $memory->{$row->{module}})) {
                $memory->{$row->{version}} = $row->{version};
            }
            next;
        }
        delete $row->{phase} unless $phase eq 'ALL';
        delete $row->{rel}   unless $rel   eq 'ALL';
        $row->{level} = $level;
        push @res, $row;
        $memory->{$row->{module}} = $row->{version};
    }

    if (@res && ($max_level==-1 || $level < $max_level)) {
        my $i = @res-1;
        while ($i >= 0) {
            my $subres = _get_prereqs($res[$i]{module}, $dbh, $memory,
                                      $level+1, $max_level, $phase, $rel, $include_core, $plver);
            $i--;
            next if $subres->[0] != 200;
            splice @res, $i+2, 0, @{$subres->[2]};
        }
    }

    [200, "OK", \@res];
}

sub _get_revdeps {
    my ($mod, $dbh) = @_;

    $log->tracef("Finding reverse dependencies for module %s ...", $mod);

    # first, check that module is listed
    my ($mod_id) = $dbh->selectrow_array("SELECT mod_id FROM mods WHERE mod_name=?", {}, $mod)
        or return [404, "No such module: $mod"];

    # get all dists that depend on that module
    my $sth = $dbh->prepare("SELECT
  (SELECT dist_name FROM dists WHERE dp.dist_id=dists.dist_id) AS dist,
  (SELECT dist_vers FROM dists WHERE dp.dist_id=dists.dist_id) AS dist_version,
  -- phase,
  -- rel,
  version req_version
FROM deps dp
WHERE mod_id=?
ORDER BY dist");
    $sth->execute($mod_id);
    my @res;
    while (my $row = $sth->fetchrow_hashref) {
        #next unless $phase eq 'ALL' || $row->{phase} eq $phase;
        #next unless $rel   eq 'ALL' || $row->{rel}   eq $rel;
        #delete $row->{phase} unless $phase eq 'ALL';
        #delete $row->{rel}   unless $rel   eq 'ALL';
        push @res, $row;
    }

    [200, "OK", \@res];
}

my %mod_args = (
    module => {
        schema => 'str*',
        req => 1,
        pos => 0,
        completion => \&_complete_mod,
    },
);

my %deps_args = (
    phase => {
        schema => ['str*' => {
            in => [qw/develop configure build runtime test ALL/],
        }],
        default => 'runtime',
    },
    rel => {
        schema => ['str*' => {
            in => [qw/requires recommends suggests conflicts ALL/],
        }],
        default => 'requires',
    },
    level => {
        summary => 'Recurse for a number of levels (-1 means unlimited)',
        schema  => 'int*',
        default => 1,
        cmdline_aliases => {
            l => {},
            R => {
                summary => 'Recurse (alias for `--level -1`)',
                is_flag => 1,
                code => sub { $_[0]{level} = -1 },
            },
        },
    },
    include_core => {
        summary => 'Include Perl core modules',
        'summary.alt.bool.not' => 'Exclude Perl core modules',
        schema  => 'bool',
        default => 0,
    },
    perl_version => {
        summary => 'Set base Perl version for determining core modules',
        schema  => 'str*',
        default => "$^V",
        cmdline_aliases => {V=>{}},
    },
);

$SPEC{'list_local_cpan_deps'} = {
    v => 1.1,
    summary => 'List dependencies of a module, data from local CPAN::SQLite database',
    args => {
        %common_args,
        %mod_args,
        %deps_args,
    },
};
sub list_local_cpan_deps {
    my %args = @_;

    my $cpan    = $args{cpan} or return [400, "Please specify 'cpan'"];
    my $mod     = $args{module};
    my $phase   = $args{phase} // 'runtime';
    my $rel     = $args{rel} // 'requires';
    my $plver   = $args{perl_version} // "$^V";
    my $level   = $args{level} // 1;
    my $include_core = $args{include_core} // 0;

    my $dbh     = _connect_db(%args);

    my $res = _get_prereqs($mod, $dbh, {}, 1, $level, $phase, $rel, $include_core, $plver);

    return $res unless $res->[0] == 200;
    for (@{$res->[2]}) {
        $_->{module} = ("  " x ($_->{level}-1)) . $_->{module};
        delete $_->{level};
    }

    $res;
}

$SPEC{'list_local_cpan_rev_deps'} = {
    v => 1.1,
    summary => 'List reverse dependencies of a module, data from local CPAN::SQLite database',
    args => {
        %common_args,
        %mod_args,
    },
};
sub list_local_cpan_rev_deps {
    my %args = @_;

    my $cpan    = $args{cpan} or return [400, "Please specify 'cpan'"];
    my $mod     = $args{module};

    my $dbh     = _connect_db(%args);

    _get_revdeps($mod, $dbh);
}

1;
# ABSTRACT:

=head1 SYNOPSIS

See the CLI scripts.


=head1 SEE ALSO

L<CPAN::SQLite> (with its front-end CLI L<cpandb>) and C<CPAN::SQLite::CPANMeta>
(with its front-end CLI C<cpandb-cpanmeta>) which generates the index database
of your local CPAN mirror.

=cut
