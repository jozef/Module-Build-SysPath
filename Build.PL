use strict;
use warnings;

my $builder = Module::Build->new(
    module_name         => 'Module::Build::SysPath',
    license             => 'perl',
    dist_author         => 'Jozef Kutej <jkutej@cpan.org>',
    dist_version_from   => 'lib/Module/Build/SysPath.pm',
    requires => {
        'File::Spec'      => 0,
        'List::MoreUtils' => 0,
        'Text::Diff'      => 0,
        'JSON::Util'      => 0,
        'Digest::MD5'     => 0,
        'Text::Diff'      => 0,
    },
    build_requires => {
        'Test::More' => 0,
        'File::Path' => 0,
    },
    add_to_cleanup      => [ 'Module-Build-SysPath-*' ],
    create_readme       => 1,
    sign                => 1,
    meta_merge => {
        resources => {
            repository => 'git://github.com/jozef/Module-Build-SysPath.git',
            bugtracker => 'http://github.com/jozef/Module-Build-SysPath/issues',
        },
        keywords => [ qw/ system paths instalation deployment applications / ],
    },
);
$builder->create_build_script();
