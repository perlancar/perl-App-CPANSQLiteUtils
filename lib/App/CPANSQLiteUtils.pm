package App::CPANSQLiteUtils;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::Any '$log';

use CPANuse Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
                       list_local_cpan_packages
                       list_local_cpan_modules
                       list_local_cpan_dists
                       list_local_cpan_authors
               );
# list_local_cpan_deps
# list_local_cpan_revdeps

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
    my $sql = "SELECT * FROM auths".
        (@where ? " WHERE ".join(" AND ", @where) : "").
            " ORDER BY cpanid";

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
        push @where, "(dist_id IN (SELECT dist_id FROM dists WHERE auth_id IN (SELECT auth_id FROM auths WHERE cpanid=?)))";
        push @bind, $args{author};
    }
    if ($args{dist}) {
        push @where, "(dist_id=(SELECT dist_id FROM dists WHERE dist_name=?))";
        push @bind, $args{dist};
    }
    my $sql = "SELECT * FROM mods".
        (@where ? " WHERE ".join(" AND ", @where) : "").
            " ORDER BY mod_name,e";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@bind);
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $detail ? $row : $row->{mod_name};
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
        push @where, "(dist_name LIKE ?)";
        push @bind, $q;
    }
    if ($args{author}) {
        push @where, "(dist_id IN (SELECT dist_id FROM dists WHERE auth_id IN (SELECT auth_id FROM auths WHERE cpanid=?)))";
        push @bind, $args{author};
    }
    my $sql = "SELECT * FROM dists".
        (@where ? " WHERE ".join(" AND ", @where) : "").
            " ORDER BY name";

    my @res;
    my $sth = $dbh->prepare($sql);
    $sth->execute(@bind);
    while (my $row = $sth->fetchrow_hashref) {
        push @res, $detail ? $row : $row->{dist_name};
    }
    \@res;
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
