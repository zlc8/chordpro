#! perl

use 5.010;

package App::Music::ChordPro;

our $VERSION = "0.72";

=head1 NAME

App::Music::ChordPro - A lyrics and chords formatting program

=head1 SYNOPSIS

  perl -MApp::Music::Chordpro -e run -- [ options ] [ file ... ]

When the associated B<chordpro> program has been installed correctly:

  chordpro [ options ] [ file ... ]

=head1 DESCRIPTION

B<chordpro> will read one or more text files containing the lyrics of
one or many songs plus chord information. B<chordpro> will then
generate a photo-ready, professional looking, impress-your-friends
sheet-music suitable for printing on your nearest printer.

B<chordpro> is a rewrite of the Chordii program, see
L<http://www.chordii.org>.

For more information about the ChordPro file format, see
L<http://www.chordpro.org>.

=cut

################ Common stuff ################

use strict;
use warnings;
use Data::Dumper;

################ The Process ################

package main;

our $config;

package App::Music::ChordPro;

sub ::run {
    my $options = app_setup( "ChordPro", $VERSION );
    binmode(STDERR, ':utf8');
    binmode(STDOUT, ':utf8');
    $options->{trace}   = 1 if $options->{debug};
    $options->{verbose} = 1 if $options->{trace};
    main($options);
}

sub main {
    my ($options) = @_;

    # Establish backend.
    my $of = $options->{output};

    if ( defined($of) && $of ne "" ) {
        if ( $of =~ /\.pdf$/i ) {
            $options->{generate} ||= "PDF";
        }
        elsif ( $of =~ /\.ly$/i ) {
            $options->{generate} ||= "LilyPond";
        }
        elsif ( $of =~ /\.(tex|ltx)$/i ) {
            $options->{generate} ||= "LaTeX";
        }
        elsif ( $of =~ /\.cho$/i ) {
            $options->{generate} ||= "ChordPro";
        }
        elsif ( $of =~ /\.msp$/i ) {
            $options->{generate} ||= "ChordPro";
            $options->{'backend-option'}->{variant} = "msp";
        }
        elsif ( $of =~ /\.(crd|txt)$/i ) {
            $options->{generate} ||= "Text";
        }
        elsif ( $of =~ /\.(debug)$/i ) {
            $options->{generate} ||= "Debug";
        }
    }
    elsif ( -t STDOUT ) {
	# No output, and stdout is terminal.
	# Derive output name from input name.
	if ( @ARGV > 1 ) {
	    # No default if more than one input document.
	    die("Please use \"--output\" to specify the output file name\n");
	}
	my $f = $ARGV[0];
	$f =~ s/\.\w+$/.pdf/;
	$f .= ".pdf" if $f eq $ARGV[0];
	$options->{output} = $f;
	warn("Writing output to $f\n") if $options->{verbose};
    }
    else {
	# Write output to stdout.
	$options->{output} = "-";
    }

    $options->{generate} ||= "PDF";
    my $pkg = "App::Music::ChordPro::Output::".$options->{generate};
    eval "require $pkg;";
    die("No backend for ", $options->{generate}, "\n$@") if $@;
    $options->{backend} = $pkg;

    # One configurator to bind them all.
    use App::Music::ChordPro::Config;
    $::config = App::Music::ChordPro::Config::configurator($options);

    # Parse the input(s).
    use App::Music::ChordPro::Songbook;
    my $s = App::Music::ChordPro::Songbook->new;
    $s->parsefile( $_, $options ) foreach @::ARGV;

    if ( $options->{'dump-chords'} ) {
	my $d = App::Music::ChordPro::Song->new;
	$d->{title} = "ChordPro $VERSION Built-in Chords";
	$d->{subtitle} = [ "http://www.chordpro.org" ];
	my @body;
	my @chords;

	my $prev = "";
	foreach my $c ( @{ App::Music::ChordPro::Chords::chordnames() } ) {
	    if ( $c =~ /^(.[b#]?)/ and $1 ne $prev )  {
		$prev = $1;
		push( @body, { type => "chord-grids",
			       context => "",
			       origin => "__CLI__",
			       chords => [ @chords ]
			     } ) if @chords;
		@chords = ();
	    }
	    push( @chords, $c );
	}

	push( @body, { type => "chord-grids",
		       context => "",
		       origin => "__CLI__",
		       chords => [ @chords ]
		     } ) if @chords;

	$d->{body} = \@body;
	if ( @{ $s->{songs} } == 1
	     && !exists $s->{songs}->[0]->{body} ) {
	    $s->{songs} = [ $d ];
	}
	else {
	    push( @{ $s->{songs} }, $d );
	}
    }

    warn(Dumper($s), "\n") if $options->{debug};

    # Generate the songbook.
    my $res = $pkg->generate_songbook( $s, $options );

    # Some backends write output themselves, others return an
    # array of lines to be written.
    if ( $res && @$res > 0 ) {
        if ( $of && $of ne "-" ) {
            open( my $fd, '>', $of );
	    binmode( $fd, ":utf8" );
	    print { $fd } ( join( "\n", @$res ) );
	    close($fd);
        }
	else {
	    binmode( STDOUT, ":utf8" );
	    print( join( "\n", @$res ) );
	}
	# Don't close STDOUT!
    }
}

################ Options and Configuration ################

=head1 COMMAND LINE OPTIONS

=over 4

=item B<--about> (short: B<-A>)

About ChordPro.

=item B<--encoding=>I<ENC>

Specify the encoding for input files. Default is UTF-8.
ISO-8859.1 (Latin-1) encoding is automatically sensed.

=item B<--lyrics-only> (short: B<-l>)

Only prints lyrics. All chords are suppressed.

Useful to make prints for singers and other musicians that do not
require chords.

=item B<--output=>I<FILE> (short: B<-o>)

Designates the name of the output file where the results are written
to.

The filename extension determines the type of the output. It should
correspond to one of the backends that are currently supported:

=over 6

=item pdf

Portable document format (PDF).

If a table of contents is generated with the PDF, ChordPro also writes
a CSV file containing titles and page numbers. This CSV file has the
same name as the PDF, with extenstion C<pdf> replaced by <csv>.

=item txt

A textual representation of the input, mostly for visual inspection.

=item cho

A functional equivalent version of the ChordPro input.

=back

=item B<--config=>I<JSON> (shorter: B<--cfg>)

A JSON file that defines the behaviour of the program and the layout
of the output. See L<App::Music::ChordPro::Config> for details.

This option may be specified more than once. Each additional config
file overrides the corresponding definitions that are currently
active.

=item B<--start-page-number=>I<N> (short: B<-p>)

Sets the starting page number for the output.

=item B<--toc> (short: B<-i>)

Includes a table of contents.

By default a table of contents is included in the PDF output when
it contains more than one song.

=item B<--no-toc>

Suppresses the table of contents.

=item B<--transpose=>I<N> (short: -x)

Transposes all songs by I<N> semi-tones. Note that I<N> may be
specified as B<+>I<N> to transpose upward, using sharps, or as
B<->I<N> to transpose downward, using flats.

=item B<--user-chord-grids>

Prints chord grids of all user defined chords used in a song.

=item B<--version> (short: B<-V>)

Prints the program version and exits.

=back

=head2 Chordii compatibility options

The following Chordii command line options are recognized. Note that
not all of them actually do something.

Options marked with * are better specified in the config file.

=over 4

=item B<--text-font=>I<FONT> (short: B<-T>) *

Sets the font used to print lyrics and comments.

I<FONT> can be either a full path name to a TrueType font file, or the
name of one of the standard fonts. See section L</FONTS> for more
details.

=item B<--text-size=>I<N> (short: B<-t>) *

Sets the font size for lyrics and comments.

=item B<--chord-font=>I<FONT> (short: B<-C>) *

Sets the font used to print the chord names.

I<FONT> can be either a full path name to a TrueType font file, or the
name of one of the standard fonts. See section L</FONTS> for more
details.

=item B<--chord-size=>I<N> (short: B<-c>) *

Sets the font size for the chord names.

=item B<--chord-grid-size=>I<N> (short: B<-s>) *

Sets chord grid size (the total width of a chord grid).

=item B<--chord-grids>

Prints chord grids of all chords used in a song.

=item B<--no-chord-grids> (short: B<-G>) *

Disables printing of chord grids of the chords used in a song.

=item B<--easy-chord-grids>

Not supported.

=item B<--no-easy-chord-grids> (short: B<-g>)

Not supported.

=item B<--chord-grids-sorted> (short: B<-S>) *

Prints chord grids of the chords used in a song, ordered by key and
type.

=item B<--no-chord-grids-sorted> *

Prints chord grids in the order they appear in the song.

=item B<--even-pages-number-left> (short B<-L>)

Prints even/odd pages with pages numbers left on even pages.

=item B<--odd-pages-number-left>

Prints even/odd pages with pages numbers left on odd pages.

=item B<--page-size=>I<FMT> (short: B<-P>) *

Specifies page size, e.g. C<a4> (default), C<letter>.

=item B<--single-space> (short B<-a>)) *

When a lyrics line has no chords associated, suppresses the vertical
space normally occupied by the chords.

=item B<--vertical-space=>I<N> (short: B<-w>) *

Adds some extra vertical space between the lines.

=item B<--2-up> (short: B<-2>)

Not supported.

=item B<--4-up> (short: B<-4>)

Not supported.

=item B<--page-number-logical> (short: B<-n>)

Not supported.

=item B<--dump-chords> (short: B<-D>)

Dumps a list of built-in chords in a form dependent of the backend used.
The PDF backend will produce neat pages of chord diagrams.
The ChordPro backend will produce a list of C<define> directives.

=item B<--dump-chords-text> (short: B<-d>)

Dumps a list of built-in chords in the form of C<define> directives,
and exits.

=back

=head2 Configuration options

See L<App::Music::ChordPro::Config> for details about the configuration
files.

Note that missing default configuration files are silently ignored.
Also, B<chordpro> will never create nor write configuration files.

=over

=item B<--sysconfig=>I<CFG>

Designates a system specific config file.

The default system config file depends on the operating system and user
environment. A common value is C</etc/chordpro.json> on Linux systems.

This is the place where the system manager can put settings like the
paper size, assuming that all printers use the same size.

=item B<--nosysconfig>

Don't use the system specific config file, even if it exists.

=item B<--nolegacyconfig>

Don't use a legacy config file, even if it exists.

=item B<--userconfig=>I<CFG>

Designates the config file for the user.

The default user config file depends on the operating system and user
environment. Common values are C<$HOME/.config/chordpro/chordpro.json>
and C<$HOME/.chordpro/chordpro.json>, where C<$HOME> indicates the
user home directory.

Here you can put settings for your preferred fonts and other layout
parameters that you want to apply to all B<chordpro> runs.

=item B<--nouserconfig>

Don't use the user specific config file, even if it exists.

=item B<--config=>I<CFG> (shorter: B<--cfg>)

Designates the config file specific for this run.

Default is a file named C<chordpro.json> in the current directory.

Here you can put settings that apply to the files in this
directory only.

You can specify multiple config files. The settings are accumulated.

=item B<--noconfig>

Don't use the specific config file, even if it exists.

=item B<--define=>I<item>

Sets a configuration item. I<item> must be in the format of
colon-separated configuration keys, an equal sign, and the value. For
example, the equivalent of B<--no-chord-grids> is
B<--define=chordgrid:show=0>.

B<--define> may be used multiple times to set multiple items.

=item B<--no-default-configs> (short: B<-X>)

Do not use any config files except the ones mentioned explicitly on
the command line.

This guarantees that the program is running with the default
configuration.

=item B<--print-default-config>

Prints the default configuration, and exits.

The default configuration is commented to explain its contents.

=item B<--print-final-config>

Prints the final configuration (after processing all system, user and
other config files), and exits.

The final configuration is not commented. Sorry.

=back

=head2 Miscellaneous options

=over

=item B<--help> (short: -h)

Prints help message. No other output is produced.

=item B<--manual>

Prints the manual. No other output is produced.

=item B<--ident>

Shows the program name and version.

=item B<--verbose>

Provides more verbose information of what is going on.

=back

=cut

use Getopt::Long 2.13 qw( :config no_ignorecase );
use File::Spec;

# Package name.
my $my_package;
# Program name and version.
my ($my_name, $my_version);
my %configs;

sub app_setup {
    my ($appname, $appversion, %args) = @_;
    my $help = 0;               # handled locally
    my $manual = 0;             # handled locally
    my $ident = 0;              # handled locally
    my $about = 0;              # handled locally
    my $version = 0;            # handled locally
    my $defcfg = 0;		# handled locally
    my $fincfg = 0;		# handled locally
    my $dump_chords = 0;	# handled locally

    # Package name.
    $my_package = $args{package};
    # Program name and version.
    if ( defined $appname ) {
        ($my_name, $my_version) = ($appname, $appversion);
    }
    else {
        ($my_name, $my_version) = qw( MyProg 0.01 );
    }

    # Config files.
    my $app_lc = lc($my_name);
    if ( -d "/etc" ) {          # some *ux
        $configs{sysconfig} =
          File::Spec->catfile( "/", "etc", "$app_lc.json" );
    }

    my $e = $ENV{CHORDIIRC} || $ENV{CHORDRC};
    if ( $ENV{HOME} && -d $ENV{HOME} ) {
        if ( -d File::Spec->catfile( $ENV{HOME}, ".config" ) ) {
            $configs{userconfig} =
              File::Spec->catfile( $ENV{HOME}, ".config", $app_lc, "$app_lc.json" );
        }
        else {
            $configs{userconfig} =
              File::Spec->catfile( $ENV{HOME}, ".$app_lc", "$app_lc.json" );
        }
	$e ||= File::Spec->catfile( $ENV{HOME}, ".chordrc" );
    }
    $e ||= "/chordrc";		# Windows, most likely
    $configs{legacyconfig} = $e if -s $e && -r _;

    if ( -s ".$app_lc.json" ) {
        $configs{config} = ".$app_lc.json";
    }
    else {
        $configs{config} = "$app_lc.json";
    }

    my $options =
      {
       verbose          => 0,           # verbose processing
       encoding         => "",          # input encoding, default UTF-8

       ### ADDITIONAL CLI OPTIONS ###

       'vertical-space' => 0,           # extra vertical space between lines
       'lyrics-only'    => 0,           # suppress all chords

       ### NON-CLI OPTIONS ###

       'chords-column'  => 0,           # chords in a separate column

       # Development options (not shown with -help).
       debug            => 0,           # debugging
       trace            => 0,           # trace (show process)

       # Service.
       _package         => $my_package,
       _name            => $my_name,
       _version         => $my_version,
       _stdin           => \*STDIN,
       _stdout          => \*STDOUT,
       _stderr          => \*STDERR,
       _argv            => [ @ARGV ],
      };

    # Colled command line options in a hash, for they will be needed
    # later.
    my $clo = {};

    # Sorry, layout is a bit ugly...
    if ( !GetOptions
         ($clo,

          ### Options ###

          "output|o=s",                 # Saves the output to FILE
          "lyrics-only",                # Suppress all chords
          "generate=s",
          "backend-option|bo=s\%",
          "encoding=s",
          "user-chord-grids!",          # Do[esn't] print grids for user defined chords.

          ### Standard Chordii Options ###

          "about|A" => \$about,         # About...
          "chord-font|C=s",             # Sets chord font
          "chord-grid-size|s=f",        # Sets chord grid size [30]
          "chord-grids-sorted|S!",      # Prints chord grids ordered
          "chord-size|c=i",             # Sets chord size [9]
          "dump-chords|D",              # Dumps chords definitions (PostScript)
          "dump-chords-text|d" => \$dump_chords,  # Dumps chords definitions (Text)
          "even-pages-number-left|L",   # Even pages numbers on left
          "odd-pages-number-left",      # Odd pages numbers on left
          "lyrics-only|l",              # Only prints lyrics
          "chord-grids|G!",             # En[dis]ables printing of chord grids
          "easy-chord-grids|g!",        # Do[esn't] print grids for built-in "easy" chords.
          "page-number-logical|n",      # Numbers logical pages, not physical
          "page-size|P=s",              # Specifies page size [letter, a4 (default)]
          "single-space|a!",            # Automatic single space lines without chords
          "start-page-number|p=i",      # Starting page number [1]
          "text-size|t=i",              # Sets text size [12]
          "text-font|T=s",              # Sets text font
          "i" => sub { $clo->{toc} = 1 },
          "toc!",                       # Generates a table of contents
          "transpose|x=i",              # Transposes by N semi-tones
          "version|V" => \$version,     # Prints version and exits
          "vertical-space|w=f",         # Extra vertical space between lines
          "2-up|2",                     # 2 pages per sheet
          "4-up|4",                     # 4 pages per sheet

          ### Configuration handling ###

          'config|cfg=s@',
          'noconfig|no-config',
          'sysconfig=s',
          'nosysconfig|no-sysconfig',
          'userconfig=s',
          'nouserconfig|no-userconfig',
	  'nolegacyconfig|no-legacy-config',
	  'nodefaultconfigs|no-default-configs|X',
	  'define=s%',
	  'print-default-config' => \$defcfg,
	  'print-final-config'   => \$fincfg,

          ### Standard options ###

          'ident'               => \$ident,
          'help|h|?'            => \$help,
          'help-config'         => sub { $manual = 2 },
          'manual'              => \$manual,
          'verbose|v',
          'trace',
          'debug',

         ) )
    {
        # GNU convention: message to STDERR upon failure.
        app_usage(\*STDERR, 2);
    }

    my $pod2usage = sub {
        # Load Pod::Usage only if needed.
        require Pod::Usage;
        Pod::Usage->import;
        unshift( @_,
		 -input => App::Packager::GetResource
		 ( $manual == 2 ? "pod/Config.pod" : "pod/ChordPro.pod" ) );
        &pod2usage;
    };

    # GNU convention: message to STDOUT upon request.
    app_ident(\*STDOUT) if $ident || $help || $manual;
    if ( $manual or $help ) {
        app_usage(\*STDOUT, 0) if $help;
        $pod2usage->(VERBOSE => 2) if $manual;
    }
    app_ident(\*STDOUT, 0) if $version;
    app_about(\*STDOUT, 0) if $about;

    # If the user specified a config, it must exist.
    # Otherwise, set to a default.
    for my $config ( qw(sysconfig userconfig legacyconfig) ) {
        for ( $clo->{$config} ) {
            if ( defined($_) ) {
                die("$_: $!\n") unless -r $_;
                next;
            }
	    # Use default.
	    next if $clo->{nodefaultconfigs};
	    next unless $configs{$config};
            $_ = $configs{$config};
            undef($_) unless -r $_;
        }
    }
    for my $config ( qw(config) ) {
        for ( $clo->{$config} ) {
            if ( defined($_) ) {
                foreach ( @$_ ) {
                    die("$_: $!\n") unless -r $_;
                }
                next;
            }
	    # Use default.
	    next if $clo->{nodefaultconfigs};
	    next unless $configs{$config};
            $_ = [ $configs{$config} ];
            undef($_) unless -r $_->[0];
        }
    }
    # If no config was specified, and no default is available, force no.
    for my $config ( qw(sysconfig userconfig config legacyconfig) ) {
        $clo->{"no$config"} = 1 unless $clo->{$config};
    }

    # Plug in command-line options.
    @{$options}{keys %$clo} = values %$clo;
    # warn(Dumper($options), "\n") if $options->{debug};

    if ( $defcfg || $fincfg ) {
	print App::Music::ChordPro::Config::config_defaults()
	  if $defcfg;
	print App::Music::ChordPro::Config::config_final($options)
	  if $fincfg;
	exit 0;
    }

    if ( $dump_chords ) {
	require App::Music::ChordPro::Chords;
	App::Music::ChordPro::Chords::dump_chords();
	exit 0;
    }

    # Return result.
    $options;
}

sub app_ident {
    my ($fh, $exit) = @_;
    print {$fh} ("This is ",
                 $my_package
                 ? "$my_package [$my_name $my_version]"
                 : "$my_name version $my_version",
                 "\n");
    exit $exit if defined $exit;
}

sub app_about {
    my ($fh, $exit) = @_;
    print ${fh} <<EndOfAbout;

ChordPro: A lyrics and chords formatting program.

ChordPro will read a text file containing the lyrics of one or many
songs plus chord information. ChordPro will then generate a
photo-ready, professional looking, impress-your-friends sheet-music
suitable for printing on your nearest printer.

To learn more about ChordPro, look for the man page or do
"chordpro --help" for the list of options.

For more information, see http://www.chordpro.org .

EndOfAbout

    my $fmt = " %-22.22s %s\n";

    print( "Run-time information:\n" );
    printf( $fmt, "ChordPro version", $VERSION );
    printf( $fmt, "Perl version", $^V );
    printf( $fmt, App::Packager::Packager(), App::Packager::Version() )
      if $App::Packager::PACKAGED;
    exit $exit if defined $exit;
}

sub app_usage {
    my ($fh, $exit) = @_;
    print ${fh} <<EndOfUsage;
Usage: $0 [ options ] [ file ... ]

Options:
    --about  -A                   About ChordPro...
    --encoding=ENC                Encoding for input files (UTF-8)
    --lyrics-only  -l             Only prints lyrics
    --output=FILE  -o             Saves the output to FILE
    --config=JSON  --cfg          Config definitions (multiple)
    --start-page-number=N  -p     Starting page number [1]
    --toc --notoc -i              Generates/suppresses a table of contents
    --transpose=N  -x             Transposes by N semi-tones
    --user-chord-grids		  Prints the user defined chords in the song
    --version  -V                 Prints version and exits

Chordii compatibility.
Options marked with * are better specified in the config file.
Options marked with - are ignored.
    --chord-font=FONT  -C         *Sets chord font
    --chord-grid-size=N  -s       *Sets chord grid size [30]
    --chord-grids-sorted  -S      *Prints chord grids ordered by key
    --chord-size=N  -c            *Sets chord size [9]
    --dump-chords  -D             Dumps chords definitions (PostScript)
    --dump-chords-text  -d        Dumps chords definitions (Text)
    --even-pages-number-left  -L  *Even pages numbers on left
    --odd-pages-number-left       *Odd pages numbers on left
    --no-chord-grids  -G          *Disables printing of chord grids
    --no-easy-chord-grids  -g     Not supported
    --page-number-logical  -n     -Numbers logical pages, not physical
    --page-size=FMT  -P           *Specifies page size [letter, a4 (default)]
    --single-space  -a            *Automatic single space lines without chords
    --text-size=N  -t             *Sets text size [12]
    --text-font=FONT  -T          *Sets text font
    --vertical-space=N  -w        *Extra vertical space between lines
    --2-up  -2                    Not supported
    --4-up  -4                    Not supported

Configuration options:
    --config=CFG        Project specific config file ($configs{config})
    --noconfig          Don't use a project specific config file
    --userconfig=CFG    User specific config file ($configs{userconfig})
    --nouserconfig      Don't use a user specific config file
    --sysconfig=CFG     System specific config file ($configs{sysconfig})
    --nosysconfig       Don't use a system specific config file
    --nolegacyconfig    Don't use a Chord/Chordii legacy config file
    --nodefaultconfigs  -X  Don't use any default config files
    --define=XXX=YYY	Sets config item XXX to value YYY
    --print-default-config   Prints the default config and exits
    --print-final-config   Prints the resultant config and exits
Missing default configuration files are silently ignored.

Miscellaneous options:
    --help  -h          This message
    --help-config       Help for ChordPro configuration
    --manual            The full manual.
    --ident             Show identification
    --verbose           Verbose information
EndOfUsage
    exit $exit if defined $exit;
}

=head1 FONTS

There are two ways to specify fonts: with a font filename, and a
built-in font name.

A font filename must be either and absolute filename, or a relative
filename which is interpreted relative to the configuration setting
C<fontdir>. In any case, the filename should point to a valid TrueType
(C<.ttf>) or OpenType (C<.otf>) font.

If it is not a filename, it must be the name one of the built-in fonts.

Built-in 'Adobe Core Fonts':

  Courier                             Symbol
  Courier-Bold                        Times-Bold
  Courier-BoldOblique                 Times-BoldItalic
  Courier-Oblique                     Times-Italic
  Helvetica                           Times-Roman
  Helvetica-Bold                      ZapfDingbats
  Helvetica-BoldOblique
  Helvetica-Oblique

Buitl-in 'Windows Fonts':

  Georgia                             Webdings
  Georgia,Bold                        Wingdings
  Georgia,BoldItalic
  Georgia,Italic
  Verdana
  Verdana,Bold
  Verdana,BoldItalic
  Verdana,Italic

=head1 MOTIVATION

Why a rewrite of Chordii?

Chordii is the de facto reference implementation of the ChordPro file
format standard. It implements ChordPro version 4.

ChordPro version 5 adds a number of new features, and this was pushing
the limits of the very old program. Unicode support would have been
very hard to add, and the whole program centered around PostScript
generation, while nowadays PDF would be a much better alternative.

So I decided to create a new reference implementation from the ground
up. I chose a programming language that is flexible and very good at
handling Unicode data. And that is fun to program in.

=head1 CURRENT STATUS

This program provides alpha support for ChordPro version 5. It
supports most of the features of Chordii, and a lot more:

* Native PDF generation

* Unicode support (all input is UTF8)

* User defined chords and tuning, not limited to 6 strings.

* Support for external TrueType and OpenType fonts

* Font kerning (with external TrueType fonts)

* Fully customizable layout, fonts and sizes

* Customizable backends for PDF, ChordPro, LilyPond*, LaTeX* and HTML*.

(* = under development)

=head1 LICENSE

Copyright (C) 2010,2016 Johan Vromans,

This module is free software. You can redistribute it and/or
modify it under the terms of the Artistic License 2.0.

This program is distributed in the hope that it will be useful,
but without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.

=cut

1;
