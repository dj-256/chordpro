#! perl

use strict;
use warnings;

# Implementation of App::Music::ChordPro::Wx::Main_wxg details.

package App::Music::ChordPro::Wx::Main;

# App::Music::ChordPro::Wx::Main_wxg is generated by wxGlade and contains
# all UI associated code.

use base qw( App::Music::ChordPro::Wx::Main_wxg );

use Wx qw[:everything];
use Wx::Locale gettext => '_T';

use App::Music::ChordPro::Wx;
use App::Music::ChordPro;
use App::Packager;
use File::Temp qw( tempfile );
use Encode qw(decode_utf8);

our $VERSION = $App::Music::ChordPro::Wx::VERSION;

sub new {
    my $self = bless $_[0]->SUPER::new(), __PACKAGE__;

    Wx::Event::EVT_IDLE($self, $self->can('OnIdle'));

    $self;
}

use constant FONTSIZE => 12;

my @fonts =
  ( { name => "Monospace",
      font => Wx::Font->new( FONTSIZE, wxFONTFAMILY_TELETYPE,
			     wxFONTSTYLE_NORMAL,
			     wxFONTWEIGHT_NORMAL ),
    },
    { name => "Serif",
      font => Wx::Font->new( FONTSIZE, wxFONTFAMILY_ROMAN,
			     wxFONTSTYLE_NORMAL,
			     wxFONTWEIGHT_NORMAL ),
    },
    { name => "Sans serif",
      font => Wx::Font->new( FONTSIZE, wxFONTFAMILY_SWISS,
			     wxFONTSTYLE_NORMAL,
			     wxFONTWEIGHT_NORMAL ),
    },
  );

my $prefctl;

# Explicit (re)initialisation of this class.
sub init {
    my ( $self, $options ) = @_;

    $prefctl ||=
      {
       cfgpreset => lc(_T("Default")),
       xcode => "",
       notation => "",
       skipstdcfg => 1,
       configfile => "",
       pdfviewer => "",
       editfont => 0,
       editsize => FONTSIZE,
      };

    if ( $^O =~ /^mswin/i ) {
	Wx::ConfigBase::Get->SetPath("/wxchordpro");
    }
    else {
	my $cb;
	if ( -d "$ENV{HOME}/.config" ) {
	    $cb = "$ENV{HOME}/.config/wxchordpro/wxchordpro";
	    mkdir("$ENV{HOME}/.config/wxchordpro");
	}
	else {
	    $cb = "$ENV{HOME}/.wxchordpro";
	}
	unless ( -f $cb ) {
	    open( my $fd, '>', $cb );
	}
	Wx::ConfigBase::Set
	    (Wx::FileConfig->new
	     ( "WxChordPro",
	       "ChordPro_ORG",
	       $cb,
	       '',
	       wxCONFIG_USE_LOCAL_FILE,
	     ));
    }

    $self->{_verbose} = $options->{verbose};
    $self->{_trace}   = $options->{trace};
    $self->{_debug}   = $options->{debug};

    $self->GetPreferences;
    my $font = $fonts[$self->{prefs_editfont}]->{font};
    $font->SetPointSize($self->{prefs_editsize});
    $self->{t_source}->SetFont($font);

    # Disable menu items if we cannot.
    $self->{main_menubar}->FindItem(wxID_UNDO)
      ->Enable($self->{t_source}->CanUndo);
    $self->{main_menubar}->FindItem(wxID_REDO)
      ->Enable($self->{t_source}->CanRedo);

    Wx::Log::SetTimestamp(' ');
    if ( @ARGV && -s $ARGV[0] ) {
	$self->openfile( shift(@ARGV) );
	return 1;
    }

    $self->opendialog;
    $self->newfile unless $self->{_currentfile};
    return 1;
}

################ Internal methods ################

# List of available config presets (styles).
my $stylelist;
sub stylelist {
    return $stylelist if $stylelist && @$stylelist;
    my $cfglib = getresource("config");
    $stylelist = [];
    if ( -d $cfglib ) {
	opendir( my $dh, $cfglib );
	foreach ( sort readdir($dh) ) {
	    $_ = decode_utf8($_);
	    next unless /^(.*)\.json$/;
	    my $base = $1;
	    unshift( @$stylelist, $base ), next
	      if $base eq "chordpro"; # default
	    push( @$stylelist, $base );
	}
    }
    push( @$stylelist, "custom" );
    return $stylelist;
}

# List of available notation systems.
my $notationlist;
sub notationlist {
    return $notationlist if $notationlist && @$notationlist;
    my $cfglib = getresource("notes");
    $notationlist = [ undef ];
    if ( -d $cfglib ) {
	opendir( my $dh, $cfglib );
	foreach ( sort readdir($dh) ) {
	    $_ = decode_utf8($_);
	    next unless /^(.*)\.json$/;
	    my $base = $1;
	    $notationlist->[0] = "common", next
	      if $base eq "common";
	    push( @$notationlist, $base )
	}
    }
    return $notationlist;
}

sub fonts { \@fonts }

sub opendialog {
    my ($self) = @_;
    my $fd = Wx::FileDialog->new
      ($self, _T("Choose ChordPro file"),
       "", "",
       "ChordPro files (*.cho,*.crd,*.chopro,*.chord,*.chordpro,*.pro)|*.cho;*.crd;*.chopro;*.chord;*.chordpro;*.pro|All files|*.*",
       0|wxFD_OPEN|wxFD_FILE_MUST_EXIST,
       wxDefaultPosition);
    my $ret = $fd->ShowModal;
    if ( $ret == wxID_OK ) {
	$self->openfile( $fd->GetPath );
    }
    $fd->Destroy;
}

sub openfile {
    my ( $self, $file ) = @_;
    unless ( $self->{t_source}->LoadFile($file) ) {
	my $md = Wx::MessageDialog->new
	  ( $self,
	    "Error opening $file: $!",
	    "File open error",
	    wxOK | wxICON_ERROR );
	$md->ShowModal;
	$md->Destroy;
	return;
    }
    #### TODO: Get rid of selection on Windows
    $self->{_currentfile} = $file;
    if ( $self->{t_source}->GetValue =~ /^\{\s*t(?:itle)[: ]+([^\}]*)\}/m ) {
	my $n = $self->{t_source}->GetNumberOfLines;
	Wx::LogStatus("Loaded: $1 ($n line" .
		      ( $n == 1 ? "" : "s" ) .
		      ")");
	$self->{sz_source}->GetStaticBox->SetLabel($1);
    }
    $self->SetTitle( $self->{_windowtitle} = $file);

    $self->{prefs_xpose} = 0;
    $self->{prefs_xposesharp} = 0;
}

sub newfile {
    my ( $self ) = @_;
    undef $self->{_currentfile};
    $self->{t_source}->SetValue( <<EOD );
{title: New Song}

EOD
    Wx::LogStatus("New file");
    $self->{prefs_xpose} = 0;
    $self->{prefs_xposesharp} = 0;
}

my ( $preview_cho, $preview_pdf );
my ( $msgs, $fatal, $died );

sub _warn {
    Wx::LogWarning(@_);
    $msgs++;
}

sub _die {
    Wx::LogError(@_);
    $msgs++;
    $fatal++;
    $died++;
}

sub preview {
    my ( $self ) = @_;

    # We can not unlink temps because we do not know when the viewer
    # is ready. So the best we can do is reuse the files.
    unless ( $preview_cho ) {
	( undef, $preview_cho ) = tempfile( OPEN => 0 );
	$preview_pdf = $preview_cho . ".pdf";
	$preview_cho .= ".cho";
	unlink( $preview_cho, $preview_pdf );
    }

    my $mod = $self->{t_source}->IsModified;
    $self->{t_source}->SaveFile($preview_cho);
    $self->{t_source}->SetModified($mod);

    #### ChordPro

    @ARGV = ();			# just to make sure
    $::__EMBEDDED__ = 1;

    $msgs = $fatal = $died = 0;
    $SIG{__WARN__} = \&_warn;
#    $SIG{__DIE__}  = \&_die;

    my $haveconfig;
    push( @ARGV, '--nosysconfig', '--nouserconfig', '--nolegacyconfig' )
      if $self->{prefs_skipstdcfg};
    if ( $self->{prefs_cfgpreset} ) {
	$haveconfig++;
	foreach ( @{ $self->{prefs_cfgpreset} } ) {
	    if ( $_ eq "custom" ) {
		push( @ARGV, '--config', $self->{prefs_configfile} );
	    }
	    else {
		push( @ARGV, '--config', $_ );
	    }
	}
    }
    if ( $self->{prefs_xcode} ) {
	$haveconfig++;
	push( @ARGV, '--transcode', $self->{prefs_xcode} );
    }
    if ( $self->{prefs_notation} ) {
	$haveconfig++;
	push( @ARGV, '--config', 'notes:' . $self->{prefs_notation} );
    }
    push( @ARGV, '--noconfig' ) unless $haveconfig;

    push( @ARGV, '--output', $preview_pdf );
    push( @ARGV, '--generate', "PDF" );

    push( @ARGV, '--transpose', $self->{prefs_xpose} )
      if $self->{prefs_xpose};

    push( @ARGV, $preview_cho );

    if ( $self->{_trace} || $self->{_debug}
	 || $self->{_verbose} && $self->{_verbose} > 1 ) {
	warn( "Command line: @ARGV\n" );
	warn( "$_\n" ) for split( /\n+/, _aboutmsg() );
    }
    my $options;
    eval {
	$options = App::Music::ChordPro::app_setup( "ChordPro", $VERSION );
    };
    _die($@), goto ERROR if $@ && !$died;

    $options->{verbose} = $self->{_verbose} || 0;
    $options->{trace} = $self->{_trace} || 0;
    $options->{debug} = $self->{_debug} || 0;
    $options->{diagformat} = 'Line %n, %m';
    $options->{silent} = 1;

    eval {
	App::Music::ChordPro::main($options)
    };
    _die($@), goto ERROR if $@ && !$died;

    if ( -e $preview_pdf ) {
	Wx::LogStatus("Output generated, starting previewer");

	if ( my $cmd = $self->{prefs_pdfviewer} ) {
	    if ( $cmd =~ s/\%f/$preview_pdf/g ) {
	    }
	    elsif ( $cmd =~ /\%u/ ) {
		my $u = _makeurl($preview_pdf);
		$cmd =~ s/\%u/$u/g;
	    }
	    else {
		$cmd .= " \"$preview_pdf\"";
	    }
	    Wx::ExecuteCommand($cmd);
	}
	else {
	    my $wxTheMimeTypesManager = Wx::MimeTypesManager->new;
	    my $ft = $wxTheMimeTypesManager->GetFileTypeFromExtension("pdf");
	    if ( $ft && ( my $cmd = $ft->GetOpenCommand($preview_pdf) ) ) {
		Wx::ExecuteCommand($cmd);
	    }
	    else {
		Wx::LaunchDefaultBrowser($preview_pdf);
	    }
	}
    }

  ERROR:
    if ( $msgs ) {
	Wx::LogStatus( $msgs . " message" .
		       ( $msgs == 1 ? "" : "s" ) . "." );
	if ( $fatal ) {
	    Wx::LogError( "Fatal problems found!" );
	    return;
	}
	else {
	    Wx::LogWarning( "Problems found!" );
	}
    }
    unlink( $preview_cho );
}

sub _makeurl {
    my $u = shift;
    $u =~ s;\\;/;g;
    $u =~ s/([^a-z0-9---_\/.~])/sprintf("%%%02X", ord($1))/ieg;
    $u =~ s/^([a-z])%3a/\/$1:/i;	# Windows
    return "file://$u";
}

sub checksaved {
    my ( $self ) = @_;
    return 1 unless ( $self->{t_source} && $self->{t_source}->IsModified );
    if ( $self->{_currentfile} ) {
	my $md = Wx::MessageDialog->new
	  ( $self,
	    "File " . $self->{_currentfile} . " has been changed.\n".
	    "Do you want to save your changes?",
	    "File has changed",
	    0 | wxCANCEL | wxYES_NO | wxYES_DEFAULT | wxICON_QUESTION );
	my $ret = $md->ShowModal;
	$md->Destroy;
	return if $ret == wxID_CANCEL;
	if ( $ret == wxID_YES ) {
	    $self->saveas( $self->{_currentfile} );
	}
    }
    else {
	my $md = Wx::MessageDialog->new
	  ( $self,
	    "Do you want to save your changes?",
	    "Contents has changed",
	    0 | wxCANCEL | wxYES_NO | wxYES_DEFAULT | wxICON_QUESTION );
	my $ret = $md->ShowModal;
	$md->Destroy;
	return if $ret == wxID_CANCEL;
	if ( $ret == wxID_YES ) {
	    return if $self->OnSaveAs == wxID_CANCEL;
	}
    }
    return 1;
}

sub saveas {
    my ( $self, $file ) = @_;
    $self->{t_source}->SaveFile($file);
    $self->SetTitle( $self->{_windowtitle} = $file);
    Wx::LogStatus( "Saved." );
}

sub GetPreferences {
    my ( $self ) = @_;
    my $conf = Wx::ConfigBase::Get;
    for ( keys( %$prefctl ) ) {
	$self->{"prefs_$_"} = $conf->Read( "preferences/$_", $prefctl->{$_} );
    }

    # Find config setting.
    my $p = lc( $self->{prefs_cfgpreset} ) || $prefctl->{cfgpreset};
    if ( ",$p" =~ quotemeta( "," . _T("Custom") ) ) {
	$self->{_cfgpresetfile} = $self->{prefs_configfile};
    }
    my @presets;
    foreach ( @{stylelist()} ) {
	if ( ",$p" =~ quotemeta( "," . $_ ) ) {
	    push( @presets, $_ );
	}
    }
    $self->{prefs_cfgpreset} = \@presets;

    # Find transcode setting.
    $p = lc $self->{prefs_xcode} || $prefctl->{xcode};
    if ( $p ) {
	if ( $p eq lc(_T("-----")) ) {
	    $p = $prefctl->{xcode};

	}
	else {
	    my $n = "";
	    for ( @{ $self->notationlist } ) {
		next unless $_ eq $p;
		$n = $p;
		last;
	    }
	    $p = $n;
	}
    }
    $self->{prefs_xcode} = $p;
}

sub SavePreferences {
    my ( $self ) = @_;
    return unless $self;
    my $conf = Wx::ConfigBase::Get;
    local $self->{prefs_cfgpreset} = join( ",", @{$self->{prefs_cfgpreset}} );
    for ( keys( %$prefctl ) ) {
	$conf->Write( "preferences/$_", $self->{"prefs_$_"} );
    }
    $conf->Flush;
}

################ Event handlers ################

# Event handlers override the subs generated by wxGlade in the _wxg class.

sub OnOpen {
    my ( $self, $event, $create ) = @_;
    return unless $self->checksaved;

    if ( $create ) {
	$self->newfile;
    }
    else {
	$self->opendialog;
    }
}

sub OnNew {
    my( $self, $event ) = @_;
    OnOpen( $self, $event, 1 );
}

sub OnSaveAs {
    my ($self, $event) = @_;
    my $fd = Wx::FileDialog->new
      ($self, _T("Choose output file"),
       "", "",
       "*.cho",
       0|wxFD_SAVE|wxFD_OVERWRITE_PROMPT,
       wxDefaultPosition);
    my $ret = $fd->ShowModal;
    if ( $ret == wxID_OK ) {
	$self->{_currentfile} = $fd->GetPath;
	$self->{t_source}->SaveFile($fd->GetPath);
	Wx::LogStatus( "Saved." );
    }
    $fd->Destroy;
    return $ret;
}

sub OnSave {
    my ($self, $event) = @_;
    goto &OnSaveAs unless $self->{_currentfile};
    $self->saveas( $self->{_currentfile} );
}

sub OnPreview {
    my ( $self, $event ) = @_;
    $self->preview;
}

sub OnQuit {
    my ( $self, $event ) = @_;
    $self->SavePreferences;
    return unless $self->checksaved;
    $self->Close(1);
}

sub OnExit {			# called implicitly
    my ( $self, $event ) = @_;
}

sub OnUndo {
    my ($self, $event) = @_;
    $self->{t_source}->CanUndo
      ? $self->{t_source}->Undo
	: Wx::LogStatus("Sorry, can't undo yet");
}

sub OnRedo {
    my ($self, $event) = @_;
    $self->{t_source}->CanRedo
      ? $self->{t_source}->Redo
	: Wx::LogStatus("Sorry, can't redo yet");
}

sub OnCut {
    my ($self, $event) = @_;
    $self->{t_source}->Cut;
}

sub OnCopy {
    my ($self, $event) = @_;
    $self->{t_source}->Copy;
}

sub OnPaste {
    my ($self, $event) = @_;
    $self->{t_source}->Paste;
}

sub OnDelete {
    my ($self, $event) = @_;
    my ( $from, $to ) = $self->{t_source}->GetSelection;
    $self->{t_source}->Remove( $from, $to ) if $from < $to;
}

sub OnHelp_ChordPro {
    my ($self, $event) = @_;
    Wx::LaunchDefaultBrowser("https://www.chordpro.org/chordpro/index.html");
}

sub OnHelp_Config {
    my ($self, $event) = @_;
    Wx::LaunchDefaultBrowser("https://metacpan.org/pod/distribution/App-Music-ChordPro/lib/App/Music/ChordPro/Config.pm");
}

sub OnHelp_Example {
    my ($self, $event) = @_;
    return unless $self->checksaved;
    $self->openfile( getresource( "examples/swinglow.cho" ) );
    undef $self->{_currentfile};
    $self->{t_source}->SetModified(1);
}

sub OnPreferences {
    my ($self, $event) = @_;

    use App::Music::ChordPro::Wx::PreferencesDialog;
    $self->{d_prefs} ||= App::Music::ChordPro::Wx::PreferencesDialog->new($self, -1, "Preferences");
    my $ret = $self->{d_prefs}->ShowModal;
    $self->SavePreferences if $ret == wxID_OK;
}

sub _aboutmsg {
    my ( $self ) = @_;

    my $firstyear = 2016;
    my $year = 1900 + (localtime(time))[5];
    if ( $year != $firstyear ) {
	$year = "$firstyear,$year";
    }

    # Sometimes version numbers are localized...
    my $dd = sub { my $v = $_[0]; $v =~ s/,/./g; $v };

    join( "",
	  "ChordPro Preview Editor version ",
	  $dd->($App::Music::ChordPro::VERSION),
	  "\n",
	  "https://www.chordpro.org\n",
	  "Copyright $year Johan Vromans <jvromans\@squirrel.nl>\n",
	  "\n",
	  "GUI wrapper ", $dd->($VERSION), " designed with wxGlade\n\n",
	  "Perl version ", $dd->(sprintf("%vd",$^V)), "\n",
	  "wxPerl version ", $dd->($Wx::VERSION), "\n",
	  "wxWidgets version ", $dd->(Wx::wxVERSION), "\n",
	  $App::Packager::PACKAGED
	  ? App::Packager::Packager()." version ".App::Packager::Version()."\n"
	  : "",
	);
}

sub OnAbout {
    my ($self, $event) = @_;

    my $md = Wx::MessageDialog->new
      ( $self, _aboutmsg(),
	"About ChordPro",
	wxOK|wxICON_INFORMATION,
	wxDefaultPosition);
    $md->ShowModal;
    $md->Destroy;
}

sub OnIdle {
    my ( $self, $event ) = @_;
    my $f = $self->{_windowtitle} // "";
    $f = "*$f" if $self->{t_source}->IsModified;
    $self->SetTitle($f);
}

################ End of Event handlers ################

1;
