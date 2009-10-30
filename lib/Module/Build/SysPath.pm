package Module::Build::SysPath;

=encoding utf-8

=head1 NAME

Module::Build::SysPath - Module::Build subclass with Sys::Path used in new() and ACTION_install()

=head1 SYNOPSIS

    use Module::Build::SysPath;
    my $builder = Module::Build::SysPath->new(
        ...


=head1 DESCRIPTION

A subclass of L<Module::Build>.

See first L<Sys::Path>.

See L<Acme::SysPath> for example usage.

=cut

use warnings;
use strict;

our $VERSION = '0.10';

use base 'Module::Build';
use Sys::Path;
use List::MoreUtils 'any';
use FindBin '$Bin';
use Digest::MD5 qw(md5_hex);
use Text::Diff 'diff';
use File::Spec;

our $sys_path_config_name = 'SPc';

=head2 new

TODO

=cut

sub new {
	my $class = shift;
	my $builder = $class->SUPER::new(@_);
    my $module  = $builder->module_name;

    # normalize module name (some people write - instead of ::) and add config level
    $module =~ s/-/::/g;
    $module .= '::'.$sys_path_config_name;
    
    do {
        unshift @INC, File::Spec->catdir($Bin, 'lib');
        eval "use $module"; die $@ if $@;
    };
    
    my $distribution_root = Sys::Path->find_distribution_root($builder->module_name);
    
    # map conf files to array of real paths
    my @conffiles = (
        map { ref $_ eq 'ARRAY' ? File::Spec->catfile(@{$_}) : $_ }     # convert path array to file name strings
        @{$builder->{'properties'}->{'conffiles'} || []}                # all conffiles
    );
    
    my %spc_properties = (
        'path_types' => [ $module->_path_types ],
    );
    my %rename_in_system;
    my %conffiles_in_system;
    my @writefiles_in_system;
    foreach my $path_type ($module->_path_types) {
        my $sys_path     = $module->$path_type;
        my $install_path = Sys::Path->$path_type;
        
        $builder->{'properties'}->{$path_type.'_files'} ||= {};

        # store for install time retrieval
        $spc_properties{'path'}->{$path_type} = $install_path;

        # skip prefix and localstatedir those are not really destination paths
        next
            if any { $_ eq $path_type } ('prefix' ,'localstatedir');

        # prepare a list of files to install
        my $non_persistant = (any { $_ eq $path_type} qw(cachedir logdir spooldir rundir lockdir sharedstatedir webdir));
        if (-d $sys_path) {
            my %files;
            foreach my $file (@{$builder->rscan_dir($sys_path)}) {
                # skip folders
                next if -d $file;
                
                my $blib_file = $file;
                my $dest_file = $file;
                $file         =~ s/$distribution_root.//;
                $dest_file    =~ s/^$sys_path/$install_path/;
                $blib_file    =~ s/^$sys_path.//;
                $blib_file    = File::Spec->catfile($path_type, $blib_file);
                
                # skip non-persistant folders, only include explicitely wanted and .exists files
                next if
                    $non_persistant
                    and ($file !~ m/\.exists$/)
                    and (not exists $builder->{'properties'}->{$path_type.'_files'}->{$file})
                ;
                
                # print 'file>  ', $file, "\n";
                # print 'bfile> ', $blib_file, "\n";
                # print 'dfile> ', $dest_file, "\n\n";
                
                if (any { $_ eq $file } @conffiles) {
                    $conffiles_in_system{$dest_file} = md5_hex(IO::Any->slurp([$file]));
                    
                    my $diff;
                    $diff = diff($file, $dest_file, { STYLE => 'Unified' })
                        if -f $dest_file;
                    if (
                        $diff                                                   # prompt when files differ
                        and Sys::Path->changed_since_install($dest_file)        # and only if the file changed on filesystem
                    ) {
                        # prompt if to overwrite conf or not
                        if (
                            # only if the distribution conffile changed since last install
                            Sys::Path->changed_since_install($dest_file, $file)
                            and Sys::Path->prompt_cfg_file_changed(
                                $file,
                                $dest_file,
                                sub { $builder->prompt(@_) },
                            )
                        ) {
                            $rename_in_system{$dest_file} = $dest_file.'-old';
                        }
                        else {
                            $blib_file .= '-spc';
                            $dest_file .= '-spc';
                        }
                    }
                }

                # add file the the Build.PL _files list
                $files{$file} = $blib_file;

                # make the conf and state files writeable in the system
                push @writefiles_in_system, $dest_file
                    if any { $_ eq $path_type } qw(sharedstatedir sysconfdir);                
            }
            $builder->{'properties'}->{$path_type.'_files'} = \%files;
        }
                
        # set instalation paths
        $builder->{'properties'}->{'install_path'}->{$path_type} = $install_path;
        
        # add build elements of the path types
        $builder->add_build_element($path_type);
    }
    $builder->{'properties'}->{'spc'} = \%spc_properties;
    $builder->notes('rename_in_system'     => \%rename_in_system);
    $builder->notes('conffiles_in_system'  => \%conffiles_in_system);
    $builder->notes('writefiles_in_system' => \@writefiles_in_system);
    
    return $builder;
}

=head2 ACTION_install

TODO

=cut

sub ACTION_install {
    my $builder = shift;
    my $destdir = $builder->{'properties'}->{'destdir'};

    # move system file for backup (only when really installing to system)
    if (not $destdir) {
        my %rename_in_system = %{$builder->notes('rename_in_system')};
        while (my ($system_file, $new_system_file) = each %rename_in_system) {
            print 'Moving ', $system_file,' -> ', $new_system_file, "\n";
            rename($system_file, $new_system_file) or die $!;
        }
    }

    $builder->SUPER::ACTION_install(@_);

    my $module  = $builder->module_name;

    my $path_types = join('|', @{$builder->{'properties'}->{'spc'}->{'path_types'}});
    
    # normalize module name (some people write - instead of ::) and add config level
    $module =~ s/-/::/g;
    $module .= '::'.$sys_path_config_name;
    
    # get path to blib and just installed SPc.pm
    my $module_filename = $module.'.pm';
    $module_filename =~ s{::}{/}g;
    my $installed_module_filename = File::Spec->catfile(
        $builder->install_map->{File::Spec->catdir(
            $builder->blib,
            'lib',        
        )},
        $module_filename
    );
    $module_filename = File::Spec->catfile($builder->blib, 'lib', $module_filename);
    
    die 'no such file - '.$module_filename
        if not -f $module_filename;
    die 'no such file - '.$installed_module_filename
        if not -f $installed_module_filename;
    unlink $installed_module_filename;
    
    # write the new version of SPc.pm
    open(my $config_fh, '<', $module_filename) or die $!;
    open(my $real_config_fh, '>', $installed_module_filename) or die $!;
    while (my $line = <$config_fh>) {
        next if ($line =~ m/# remove after install$/);
        if ($line =~ m/^sub \s+ ($path_types) \s* {/xms) {
            $line =
                'sub '
                .$1
                ." {'"
                .$builder->{'properties'}->{'spc'}->{'path'}->{$1}
                ."'};\n"
            ;
        }
        print $real_config_fh $line;
    }
    close($real_config_fh);
    close($config_fh);
        
    # see https://rt.cpan.org/Ticket/Display.html?id=49579
    # ExtUtils::Install is forcing 0444 so we have to hack write permition after install :-/
    foreach my $writefile (@{$builder->notes('writefiles_in_system')}) {
        chmod 0644, File::Spec->catfile($destdir || (), $writefile) or die $!;
    }
    
    # record md5sum of new distribution conffiles (only when really installing to system)
    Sys::Path->install_checksums(%{$builder->notes('conffiles_in_system')})
        if (not $destdir);
    
    return;
}

1;


__END__

=head1 AUTHOR

Jozef Kutej, C<< <jkutej at cpan.org> >>

=head1 CONTRIBUTORS
 
The following people have contributed to the Sys::Path by commiting their
code, sending patches, reporting bugs, asking questions, suggesting useful
advices, nitpicking, chatting on IRC or commenting on my blog (in no particular
order):

    Lars Dɪᴇᴄᴋᴏᴡ 迪拉斯
    Emmanuel Rodriguez

=head1 BUGS

Please report any bugs or feature requests to C<bug-module-build-syspath at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Module-Build-SysPath>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

=head2 Mailing list

L<http://lists.meon.sk/mailman/listinfo/sys-path>

=head2 The rest

You can find documentation for this module with the perldoc command.

    perldoc Sys::Path

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Module-Build-SysPath>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Module-Build-SysPath>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Module-Build-SysPath>

=item * Search CPAN

L<http://search.cpan.org/dist/Module-Build-SysPath>

=back


=head1 COPYRIGHT & LICENSE

Copyright 2009 Jozef Kutej, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.


=cut

1;
