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
use File::Temp qw( tempfile );

our $VERSION = $App::Music::ChordPro::Wx::VERSION;

sub new {
    my $self = bless $_[0]->SUPER::new(), __PACKAGE__;

    $self;
}

my $prefctl;

# Explicit (re)initialisation of this class.
sub init {
    my ( $self ) = @_;

    $prefctl ||=
      {
       cfgpreset => "Default",
       skipstdcfg => 1,
       configfile => "",
       pdfviewer => "",
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
	       "Squirrel Consultancy",
	       $cb,
	       '',
	       wxCONFIG_USE_LOCAL_FILE,
	     ));
    }

    $self->GetPreferences;
    my $font = Wx::Font->new( 12, wxFONTFAMILY_MODERN, wxFONTSTYLE_NORMAL,
			      wxFONTWEIGHT_NORMAL );
    $self->{t_source}->SetFont($font);
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
    if ( $self->{t_source}->GetValue =~ /^\{\s*title[: ]+([^\}]*)\}/m ) {
	my $n = $self->{t_source}->GetNumberOfLines;
	Wx::LogStatus("Loaded: $1 ($n line" .
		      ( $n == 1 ? "" : "s" ) .
		      ")");
	$self->{sz_source}->GetStaticBox->SetLabel($1);
    }

    $self->{prefs_xpose} = 0;
}

sub newfile {
    my ( $self ) = @_;
    undef $self->{_currentfile};
    $self->{t_source}->SetValue( <<EOD );
{title: New Song}

EOD
    Wx::LogStatus("New file");
    $self->{prefs_xpose} = 0;
}

my ( $preview_cho, $preview_pdf );

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
    my $options = App::Music::ChordPro::app_setup( "ChordPro", $VERSION );

    use App::Music::ChordPro::Output::PDF;
    $options->{output} = $preview_pdf;
    $options->{generate} = "PDF";
    $options->{backend} = "App::Music::ChordPro::Output::PDF";
    $options->{transpose} = $self->{prefs_xpose} if $self->{prefs_xpose};

    # Setup configuration.
    use App::Music::ChordPro::Config;
    $options->{nouserconfig} =
      $options->{nolegacyconfig} = $self->{prefs_skipstdcfg};
    if ( $self->{_cfgpresetfile} ) {
	$options->{noconfig} = 0;
	$options->{config} = $self->{_cfgpresetfile};
    }
    else {
	$options->{noconfig} = 1;
    }
    $::config = App::Music::ChordPro::Config::configurator($options);

    # Parse the input.
    use App::Music::ChordPro::Songbook;
    my $s = App::Music::ChordPro::Songbook->new;

    my $msgs;
    my $fatal;
    $SIG{__WARN__} = sub {
	Wx::LogWarning(@_);
	$msgs++;
    };

    $options->{diagformat} = 'Line %n, %m';
    eval { $s->parsefile( $preview_cho, $options ) };
    if ( $@ ) {
	Wx::LogError($@);
	$msgs++;
	$fatal++;
    }

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

    # Generate the songbook.
    eval {
	App::Music::ChordPro::Output::PDF->generate_songbook( $s, $options )
    };
    if ( $@ ) {
	Wx::LogError($@);
	return;
    }

    if ( -e $preview_pdf ) {
	Wx::LogStatus("Output generated, starting previewer");

	if ( my $cmd = $self->{prefs_pdfviewer} ) {
	    if ( $cmd =~ s/\%f/$preview_pdf/g ) {
		$cmd .= " \"$preview_pdf\"";
	    }
	    elsif ( $cmd =~ /\%u/ ) {
		my $u = _makeurl($preview_pdf);
		$cmd =~ s/\%u/$u/g;
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
    Wx::LogStatus( "Saved." );
}

sub GetPreferences {
    my ( $self ) = @_;
    my $conf = Wx::ConfigBase::Get;
    for ( keys( %$prefctl ) ) {
	$self->{"prefs_$_"} = $conf->Read( "preferences/$_", $prefctl->{$_} );
    }
}

sub SavePreferences {
    my ( $self ) = @_;
    return unless $self;
    my $conf = Wx::ConfigBase::Get;
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
	$self->{t_source}->SaveFile($fd->GetPath);
	Wx::LogStatus( "Saved." );
    }
    $fd->Destroy;
    return $ret;
}

sub OnSave {
    my ($self, $event) = @_;
    $self->saveas( $self->{_currentfile} );
}

sub OnPreview {
    my ( $self, $event ) = @_;
    $self->preview;
}

sub OnQuit {
    my ( $self, $event ) = @_;
    return unless $self->checksaved;
    $self->SavePreferences;
    $self->Close;
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
    Wx::LaunchDefaultBrowser("http://www.chordpro.org/chordpro/index.html");
}

sub OnHelp_Config {
    my ($self, $event) = @_;
    Wx::LaunchDefaultBrowser("https://metacpan.org/pod/distribution/App-Music-ChordPro/res/pod/Config.pod");
}

sub OnHelp_Example {
    my ($self, $event) = @_;
    return unless $self->checksaved;
    $self->openfile( ::findlib( "examples/swinglow.cho" ) );
    undef $self->{_currentfile};
    $self->{t_source}->SetModified(1);
}

sub OnPreferences {
    my ($self, $event) = @_;

    use App::Music::ChordPro::Wx::PreferencesDialog;
    $self->{d_prefs} ||= App::Music::ChordPro::Wx::PreferencesDialog->new($self, -1, "Preferences");
    my $ret = $self->{d_prefs}->ShowModal;
}

sub OnAbout {
    my ($self, $event) = @_;

    my $firstyear = 2016;
    my $year = 1900 + (localtime(time))[5];
    if ( $year != $firstyear ) {
	$year = "$firstyear,$year";
    }

    # Sometimes version numbers are localized...
    my $dd = sub { my $v = $_[0]; $v =~ s/,/./g; $v };

    if ( rand > 0.5 ) {
	my $ai = Wx::AboutDialogInfo->new;
	$ai->SetName("ChordPro Preview Editor");
	$ai->SetVersion( $dd->($App::Music::ChordPro::VERSION) );
	$ai->SetCopyright("Copyright $year Johan Vromans <jvromans\@squirrel.nl>");
	$ai->AddDeveloper("Johan Vromans <jvromans\@squirrel.nl>\n");
	$ai->AddDeveloper("ChordPro version " .
			  $dd->($App::Music::ChordPro::VERSION));
	$ai->AddDeveloper("GUI wrapper " . $dd->($VERSION) . " " .
			  "designed with wxGlade\n");
	$ai->AddDeveloper("Perl version " . $dd->(sprintf("%vd",$^V)));
	$ai->AddDeveloper("wxWidgets version " . $dd->(Wx::wxVERSION));
	$ai->AddDeveloper(App::Packager::Packager() . " version " . App::Packager::Version())
	  if $App::Packager::PACKAGED;
	$ai->AddDeveloper("Some icons by www.flaticon.com");
	$ai->SetWebSite("https://www.chordpro.org");
	Wx::AboutBox($ai);
    }
    else {
	my $md = Wx::MessageDialog->new
	  ($self, "ChordPro Preview Editor version " . $dd->($App::Music::ChordPro::VERSION) . "\n".
	   "Copyright $year Johan Vromans <jvromans\@squirrel.nl>\n".
	   "\n".
	   "GUI wrapper " . $dd->($VERSION) . " ".
	   "designed with wxGlade\n\n".
	   "Perl version " . $dd->(sprintf("%vd",$^V))."\n".
	   "wxPerl version " . $dd->($Wx::VERSION)."\n".
	   "wxWidgets version " . $dd->(Wx::wxVERSION)."\n\n".
	   "https://www.chordpro.org\n".
	   ( $App::Packager::PACKAGED
	     ? App::Packager::Packager() . " version " . App::Packager::Version()."\n"
	     : "" ),
	   "About ChordPro",
	   wxOK|wxICON_INFORMATION,
	   wxDefaultPosition);
	$md->ShowModal;
	$md->Destroy;
    }
}

################ End of Event handlers ################

1;
