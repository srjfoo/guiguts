package Guiguts::FileMenu;
use strict;
use warnings;

BEGIN {
    use Exporter();
    our ( @ISA, @EXPORT );
    @ISA = qw(Exporter);
    @EXPORT =
      qw(&file_open &file_saveas &file_include &file_export_preptext &file_import_preptext &_bin_save &file_close
      &clearvars &savefile &_exit &file_mark_pages &file_guess_page_marks
      &oppopupdate &opspop_up &confirmempty &openfile &readsettings &savesettings &file_export_pagemarkup
      &file_import_markup &file_import_ocr &operationadd &isedited &setedited &charsuitespopup &charsuitecheck &charsuitefind &charsuiteenable
      &cpcharactersubs &getsafelastpath);
}

#
# Wrapper routine to find a text/HTML file and open it
sub file_open {
    my $textwindow = shift;
    my ($name);
    return if ( ::confirmempty() =~ /cancel/i );
    my $types = [
        [ 'Text Files', [qw/.txt .text .ggp .htm .html .bk1 .bk2 .xml .xhtml/] ],
        [ 'All Files',  ['*'] ],
    ];
    $name = $textwindow->getOpenFile(
        -filetypes  => $types,
        -title      => 'Open File',
        -initialdir => getsafelastpath()
    );
    if ( defined($name) and length($name) ) {
        ::openfile($name);
    }
}

#
# Find a text file to insert into the current file - must have a file currently loaded
sub file_include {
    my $textwindow = shift;
    my ($name);
    my $types = [
        [ 'Text Files', [ '.txt', '.text', '.ggp', '.htm', '.html', '.xml' ] ],
        [ 'All Files',  ['*'] ],
    ];
    return if $::lglobal{global_filename} =~ m{No File Loaded};
    $name = $textwindow->getOpenFile(
        -filetypes  => $types,
        -title      => 'File Include',
        -initialdir => getsafelastpath()
    );
    $textwindow->IncludeFile($name)
      if defined($name)
      and length($name);
    return;
}

#
# Save file as a new name
# With optional second argument, save copy of file as a new name,
# but keep the name of the currently loaded file the same
sub file_saveas {

    # Temporarily disable autosave - don't want that to happen part way through saving
    my $saveautosave = $::autosave;
    $::autosave = 0;
    ::reset_autosave();

    my $textwindow = shift;
    my $saveacopy  = shift;    # If set, then save a copy

    ::hidepagenums();
    my $initialfile = '';
    $initialfile = $::lglobal{global_filename}
      unless ( $::lglobal{global_filename} =~ m/No File Loaded/ );
    $initialfile =~ s|.*/([^/]*)$|$1|;
    my $name = $textwindow->getSaveFile(
        -title       => ( $saveacopy ? 'Save a Copy As' : 'Save As' ),
        -initialdir  => getsafelastpath(),
        -initialfile => $initialfile,
    );

    if ( defined($name) and length($name) and not bad_filename_chars($name) ) {
        $::top->Busy( -recurse => 1 );
        $textwindow->SaveUTF($name);
        $name = ::os_normal($name);
        recentupdate($name);

        # If saving a copy, globallastpath is not updated, edit flag is not reset,
        # bin_save is done using new filename, then old name is restored
        my $oldfilename = $::lglobal{global_filename};
        $::globallastpath = ::os_normal( ( ::fileparse($name) )[1] ) unless $saveacopy;
        $::lglobal{global_filename} = $name;
        _bin_save();
        if ($saveacopy) {
            $::lglobal{global_filename} = $oldfilename;
        } else {
            $textwindow->ResetUndo;
            ::setedited(0);
        }

        $textwindow->FileName( $::lglobal{global_filename} );
        $::top->Unbusy( -recurse => 1 );
    }

    # Restore autosave flag
    $::autosave = $saveautosave;
    ::reset_autosave();
}

#
# Close the currently loaded file, checking first if user needs to save
sub file_close {
    my $textwindow = shift;
    return if ( ::confirmempty() =~ m{cancel}i );
    clearvars($textwindow);
    return;
}

#
# Import prep text files and allow user to save concatenated result
sub file_import_preptext {
    my ( $textwindow, $top ) = @_;
    return if ( ::confirmempty() =~ /cancel/i );
    my $directory = $top->chooseDirectory(
        -title      => 'Choose the directory containing the text files to be imported',
        -initialdir => getsafelastpath(),
    );
    return 0
      unless ( defined $directory and -d $directory and $directory ne '' );
    $top->Busy( -recurse => 1 );
    my $pwd = ::getcwd();
    chdir $directory;
    my @files = glob "*.txt";
    chdir $pwd;
    $directory .= '/';
    $directory        = ::os_normal($directory);
    $::globallastpath = $directory;

    for my $file ( sort @files ) {
        if ( $file =~ /(\w+)\.txt$/ ) {
            $textwindow->ntinsert( 'end', ( "\n" . '-' x 5 ) );
            $textwindow->ntinsert( 'end', "File: $1.png" );
            $textwindow->ntinsert( 'end', ( '-' x 45 ) . "\n" );
            if ( open my $fh, '<', "$directory$file" ) {
                local $/ = undef;
                my $line = <$fh>;
                utf8::decode($line);
                $line =~ s/^\x{FEFF}?//;
                $line =~ s/\cM\cJ|\cM|\cJ/\n/g;
                $line =~ s/[\t \xA0]+$//smg;
                $textwindow->ntinsert( 'end', $line );
                close $file;
            }
            $top->update;
        }
    }
    $textwindow->markSet( 'insert', '1.0' );
    $::lglobal{prepfile} = 1;
    ::file_mark_pages() if ($::auto_page_marks);
    my $tmppath = $::globallastpath;
    $tmppath =~ s|[^/\\]*[/\\]$||;    # go one dir level up
    $tmppath = ::catdir( $tmppath, $::defaultpngspath );

    # ensure trailing slash
    my $slash = $::OS_WIN ? "\\" : "/";
    $tmppath .= $slash unless substr( $tmppath, -1 ) eq $slash;
    $::pngspath = $tmppath if ( -e $tmppath );
    $top->Unbusy( -recurse => 1 );

    # give user chance to save combined file - necessary for operations like character count
    file_saveas($textwindow);
    return;
}

#
# Split current file into individual pages and export as prep text files
sub file_export_preptext {
    my $exporttype       = shift;
    my $top              = $::top;
    my $textwindow       = $::textwindow;
    my $midwordpagebreak = 0;
    my $directory        = $top->chooseDirectory(
        -title      => 'Choose the directory to export the text files to',
        -initialdir => getsafelastpath(),
    );
    return 0 unless ( defined $directory and $directory ne '' );
    unless ( -e $directory ) {
        mkdir $directory or warn "Could not make directory $!\n" and return;
    }
    $top->Busy( -recurse => 1 );
    my @marks = $textwindow->markNames;
    my @pages = sort grep ( /^Pg\S+$/, @marks );
    my ( $f, $globalfilename, $e ) =
      ::fileparse( $::lglobal{global_filename}, qr{\.[^\.]*$} );
    if ( $exporttype eq 'onefile' ) {

        # delete the existing file
        open my $fh, '>', "$directory/prep.txt";
        close $fh;
    }
    while (@pages) {
        my $page = shift @pages;
        my ($filename) = $page =~ /Pg(\S+)/;
        $filename .= '.txt';
        my $next;
        if (@pages) {
            $next = $pages[0];
        } else {
            $next = 'end';
        }
        my $file = $textwindow->get( $page, $next );
        if ( not defined $file ) {
            ::warnerror(
                "Corrupt page markers detected: quit; delete bin file; delete any prep text files written; restart"
            );
            last;
        }
        if ( $midwordpagebreak and ( $exporttype eq 'onefile' ) ) {

            # put the rest of the word after the separator with a *
            $file = '*' . $file;

            # ... with the rest of the word with the following line
            $file =~ s/\n/ /;
            $midwordpagebreak = 0;
        }
        if ( $file =~ '[A-Za-z]$' and ( $exporttype eq 'onefile' ) ) {
            my $nextchar = $textwindow->get( $pages[0], $pages[0] . '+1c' );
            if ( $nextchar =~ '^[A-Za-z]' ) {
                $file .= '-*';
                $midwordpagebreak = 1;
            }
        }
        $file =~ s/-*\s?File:\s?(\S+)\.(png|jpg)---[^\n]*\n//;
        $file =~ s/\n+$//;
        utf8::encode($file);
        if ( $exporttype eq 'onefile' ) {
            open my $fh, '>>', "$directory/prep.txt";
            print $fh $file;
            print $fh ( "\n" . '-' x 5 ) . "File: $page.png" . ( '-' x 45 ) . "\n";
            close $fh;
        } else {
            open my $fh, '>', "$directory/$filename";
            print $fh $file;
            close $fh;
        }
    }
    $top->Unbusy( -recurse => 1 );
    return;
}

#
# Save the .bin file associated with the text file
# Contains locations of page breaks and bookmarks, and other project info
sub _bin_save {
    my ( $textwindow, $top ) = ( $::textwindow, $::top );
    my $mark = '1.0';
    while ( $textwindow->markPrevious($mark) ) {
        $mark = $textwindow->markPrevious($mark);
    }
    my $markindex;
    while ($mark) {
        if ( $mark =~ m{Pg(\S+)} ) {
            $markindex                    = $textwindow->index($mark);
            $::pagenumbers{$mark}{offset} = $markindex;
            $mark                         = $textwindow->markNext($mark);
        } else {
            $mark = $textwindow->markNext($mark) if $mark;
            next;
        }
    }
    return if ( $::lglobal{global_filename} =~ m{No File Loaded} );
    my $binname = "$::lglobal{global_filename}.bin";
    if ( $textwindow->markExists('spellbkmk') ) {
        $::spellindexbkmrk = $textwindow->index('spellbkmk');
    }
    my $bak = "$binname.bak";
    if ( -e $bak ) {
        my $perms = ( stat($bak) )[2] & 0777;
        unless ( $perms & 300 ) {
            $perms = $perms | 300;
            chmod $perms, $bak or warn "Can not back up .bin file: $!\n";
        }
        unlink $bak;
    }
    my $permsave;
    if ( -e $binname ) {
        my $perms = ( stat($binname) )[2] & 0777;
        $permsave = $perms;
        unless ( $perms & 300 ) {
            $perms = $perms | 300;
            chmod $perms, $binname
              or warn "Can not save .bin file: $!\n" and return;
        }
        rename $binname, $bak or warn "Can not back up .bin file: $!\n";
    }
    my $fh = FileHandle->new("> $binname");
    if ( defined $fh ) {
        binmode $fh, ":encoding(utf-8)";
        print $fh "\%::pagenumbers = (\n";
        for my $page ( sort { $a cmp $b } keys %::pagenumbers ) {
            if ( $page eq "Pg" ) {
                next;
            }

            # output page and offset
            print $fh " '$page' => {";
            print $fh "'offset' => '$::pagenumbers{$page}{offset}', "
              if defined $::pagenumbers{$page}{offset};

            # if labels have been set up, output label information too
            print $fh "'label' => '" .  ( $::pagenumbers{$page}{label}  || "" ) . "', ";
            print $fh "'style' => '" .  ( $::pagenumbers{$page}{style}  || "" ) . "', ";
            print $fh "'action' => '" . ( $::pagenumbers{$page}{action} || "" ) . "', ";
            print $fh "'base' => '" .   ( $::pagenumbers{$page}{base}   || "" ) . "'";
            print $fh "},\n";
        }
        print $fh ");\n\n";
        foreach ( keys %::operationshash ) {
            my $mark = ::escape_problems($_);
            print $fh "\$::operationshash{'$mark'}='" . $::operationshash{$_} . "';\n";
        }
        print $fh "\n";
        print $fh '$::bookmarks[0] = \'' . $textwindow->index('insert') . "';\n";
        for ( 1 .. 5 ) {
            print $fh '$::bookmarks[' . $_ . '] = \'' . $textwindow->index( 'bkmk' . $_ ) . "';\n"
              if $::bookmarks[$_];
        }
        if ($::pngspath) {
            print $fh "\n\$::pngspath = '@{[::escape_problems($::pngspath)]}';\n\n";
        }
        print $fh "\$::spellindexbkmrk = '$::spellindexbkmrk';\n\n";
        print $fh "\$::projectid = '$::projectid';\n\n";
        print $fh "\$::booklang = '$::booklang';\n\n";
        print $fh "\$::bookauthor = \"" . ::escapeforperlstring($::bookauthor) . "\";\n\n";
        print $fh
          "\$scannoslistpath = '@{[::escape_problems(::os_normal($::scannoslistpath))]}';\n\n";
        foreach ( sort keys %::charsuiteenabled ) {
            next unless $::charsuiteenabled{$_};
            print $fh "\$::charsuiteenabled{'" . ::escape_problems($_) . "'} = 1;\n";
        }
        print $fh "\n";
        print $fh '1;';
        $fh->close;
        chmod $permsave, $binname if $permsave;    # copy file permissions if overwriting
    } else {
        $top->BackTrace("Cannot open $binname:$!");
    }
    return;
}

#
# Clear persistent variables before loading another file
sub clearvars {
    my $textwindow = shift;
    my @marks      = $textwindow->markNames;
    for (@marks) {
        unless ( $_ =~ m{insert|current} ) {
            $textwindow->markUnset($_);
        }
    }
    %::reghints = ();
    ::spellquerycleardict();
    %{ $::lglobal{seenwordsdoublehyphen} } = ();
    $::lglobal{seenwords}     = ();
    $::lglobal{seenwordpairs} = ();
    $::lglobal{fnarray}       = ();
    %::pagenumbers            = ();
    %::operationshash         = ();
    %::charsuiteenabled       = ( 'Basic Latin' => 1 );    # All projects allow Basic Latin character suite
    @::bookmarks              = ();
    $::pngspath               = q{};
    ::setedited(0);
    ::hidepagenums();
    @{ $::lglobal{fnarray} } = ();
    $::lglobal{fntotal} = 0;
    undef $::lglobal{prepfile};
    $::bookauthor = '';
    $::booklang   = 'en';
    return;
}

#
# Destroy some popups and labels when closing a file
sub clearpopups {
    ::killpopup('img_num_label');
    ::killpopup('pagebutton');
    ::killpopup('previmagebutton');
    ::killpopup('footpop');
    ::killpopup('footcheckpop');
    ::killpopup('htmlgenpop');
    ::killpopup('pagelabelpop');
    ::killpopup('errorcheckpop');
}

#
# Save the currently loaded file
sub savefile {

    # Temporarily disable autosave - don't want that to happen part way through saving
    my $saveautosave = $::autosave;
    $::autosave = 0;
    ::reset_autosave();

    my ( $textwindow, $top ) = ( $::textwindow, $::top );
    my $filename = $::lglobal{global_filename};

    if ( bad_filename_chars($filename) ) {    # Do not save if filename contains illegal characters
        ;
    } elsif ( $filename =~ /No File Loaded/ ) {    # If no filename, do "Save As".
        file_saveas($textwindow);
    } else {
        ::hidepagenums();
        if (
            !fileisreadonly($filename)
            or 'Yes' eq $top->messageBox(
                -icon    => 'warning',
                -title   => 'Confirm save?',
                -type    => 'YesNo',
                -default => 'no',
                -message =>
                  "File $filename is write-protected. Remove write-protection and save anyway?",
            )
        ) {
            $::top->Busy( -recurse => 1 );
            if ( $::autobackup and -e $filename ) {    # Handle autobackup
                unlink "$filename.bk2" if -e "$filename.bk2";
                rename( "$filename.bk1", "$filename.bk2" ) if -e "$filename.bk1";
                rename( $filename, "$filename.bk1" );
            }
            $textwindow->SaveUTF;
            ::_bin_save();
            $textwindow->ResetUndo;                    # Necessary to reset edited flag
            ::setedited(0);
            $::top->Unbusy( -recurse => 1 );
        }
    }

    # Restore autosave flag
    $::autosave = $saveautosave;
    ::reset_autosave();
}

#
# Return true if file is write-protected for the owner
sub fileisreadonly {
    my $name = shift;
    my $mode = ( stat($name) )[2];
    return 0 if ( $mode & 0200 );
    return 1;
}

#
# Use page separator lines in file to locate page boundaries and set marks
sub file_mark_pages {
    my $top        = $::top;
    my $textwindow = $::textwindow;
    $top->Busy( -recurse => 1 );
    ::hidepagenums();

    # Regex must capture scan file basename in first capture group
    # and file extension in second capture group
    my $pagesepreg = 'File:.+?([^\/\\ ]+)\.(png|jpg)';

    my $lineend = '1.0';
    while ( my $linestart =
        $textwindow->search( '-nocase', '-regexp', '--', $pagesepreg, $lineend, 'end' ) ) {
        $linestart .= " linestart";
        $lineend = $textwindow->index("$linestart lineend");

        # get the page name & mark the position
        my $line = $textwindow->get( $linestart, $lineend );
        next unless $line =~ $pagesepreg;    # Can't happen since same regex as earlier
        my $page     = $1;                   # Extract scan file basename
        my $ext      = $2;                   # and file extension
        my $pagemark = 'Pg' . $page;

        # Standardize page separator line format if necessary
        unless ( $line =~ /^-----File: (\S+)\.(png|jpg)---/ ) {
            $textwindow->ntdelete( $linestart, $lineend );
            my $stdline = ( '-' x 5 ) . "File: $page.$ext";
            $stdline .= '-' x ( 75 - length($stdline) );
            $textwindow->ntinsert( $linestart, $stdline );
        }

        # Create and position page mark
        $::pagenumbers{$pagemark}{offset} = 1;
        $textwindow->markSet( $pagemark, $linestart );
        $textwindow->markGravity( $pagemark, 'left' );
    }
    $top->Unbusy( -recurse => 1 );
    return;
}

#
# Track recently open files for the menu
sub recentupdate {
    my $name = shift;

    # remove $name or any *empty* values from the list
    @::recentfile = grep( !/(?: \Q$name\E | \Q*empty*\E )/x, @::recentfile );

    # place $name at the top
    unshift @::recentfile, $name;

    # limit the list to the desired number of entries
    pop @::recentfile while ( $#::recentfile >= $::recentfile_size );
    ::menurebuild();
    return;
}

#
# Exit the program, giving the user a chance to save first if needed
sub _exit {
    if ( confirmdiscard() =~ m{no}i ) {    # "no" means ok to continue
        ::aspellstop() if $::lglobal{spellpid};
        exit;
    }
}

#
# If page markers have been corrupted/lost/not set, and file has no page separator lines,
# attempt to guess where the page markers were, given a few key locations in the file.
sub file_guess_page_marks {
    my $top        = $::top;
    my $textwindow = $::textwindow;
    my ( $totpages, $line25, $linex );
    if ( $::lglobal{guesspgmarkerpop} ) {
        $::lglobal{guesspgmarkerpop}->deiconify;
    } else {
        $::lglobal{guesspgmarkerpop} = $top->Toplevel;
        $::lglobal{guesspgmarkerpop}->title('Guess Page Markers');
        my $f0 = $::lglobal{guesspgmarkerpop}->Frame->pack;
        $f0->Label( -text =>
              'This function should only be used if you have the page images but no page markers in the text.',
        )->grid( -row => 1, -column => 1, -padx => 1, -pady => 2 );
        my $f1 = $::lglobal{guesspgmarkerpop}->Frame->pack;
        $f1->Label( -text => 'How many pages are there total?', )
          ->grid( -row => 1, -column => 1, -padx => 1, -pady => 2 );
        my $tpages =
          $f1->Entry( -width => 8, )->grid( -row => 1, -column => 2, -padx => 1, -pady => 2 );
        $f1->Label( -text => 'What line # does page 25 start with?', )
          ->grid( -row => 2, -column => 1, -padx => 1, -pady => 2 );
        my $page25 =
          $f1->Entry( -width => 8, )->grid( -row => 2, -column => 2, -padx => 1, -pady => 2 );
        my $f3 = $::lglobal{guesspgmarkerpop}->Frame->pack;
        $f3->Label( -text => 'Select a page near the back, before the index starts.', )
          ->grid( -row => 2, -column => 1, -padx => 1, -pady => 2 );
        my $f4 = $::lglobal{guesspgmarkerpop}->Frame->pack;
        $f4->Label( -text => 'Page #?.', )->grid( -row => 1, -column => 1, -padx => 1, -pady => 2 );
        $f4->Label( -text => 'Line #?.', )->grid( -row => 1, -column => 2, -padx => 1, -pady => 2 );
        my $pagexe =
          $f4->Entry( -width => 8, )->grid( -row => 2, -column => 1, -padx => 1, -pady => 2 );
        my $linexe =
          $f4->Entry( -width => 8, )->grid( -row => 2, -column => 2, -padx => 1, -pady => 2 );
        my $f2         = $::lglobal{guesspgmarkerpop}->Frame->pack;
        my $calcbutton = $f2->Button(
            -command => sub {
                my ( $pnum, $lnum, $pagex, $linex, $number );
                $totpages = $tpages->get;
                $line25   = $page25->get;
                $pagex    = $pagexe->get;
                $linex    = $linexe->get;
                unless ( $totpages && $line25 && $pagex && $linex ) {
                    $top->messageBox(
                        -icon    => 'error',
                        -message => 'Need all values filled in.',
                        -title   => 'Missing values',
                        -type    => 'Ok',
                    );
                    return;
                }
                if ( $totpages <= $pagex ) {
                    $top->messageBox(
                        -icon    => 'error',
                        -message => 'Selected page must be lower than total pages',
                        -title   => 'Bad value',
                        -type    => 'Ok',
                    );
                    return;
                }
                if ( $linex <= $line25 ) {
                    $top->messageBox(
                        -icon    => 'error',
                        -message => "Line number for selected page must be \n"
                          . "higher than that of page 25",
                        -title => 'Bad value',
                        -type  => 'Ok',
                    );
                    return;
                }
                my $end = $textwindow->index('end');
                $end = int( $end + .5 );
                my $average = ( int( $line25 + .5 ) / 25 );
                for my $pnum ( 1 .. 24 ) {
                    $lnum = int( ( $pnum - 1 ) * $average ) + 1;
                    if ( $totpages > 999 ) {
                        $number = sprintf '%04s', $pnum;
                    } else {
                        $number = sprintf '%03s', $pnum;
                    }
                    $textwindow->markSet( 'Pg' . $number, "$lnum.0" );
                    $textwindow->markGravity( "Pg$number", 'left' );
                }
                $average = ( ( int( $linex + .5 ) ) - ( int( $line25 + .5 ) ) ) / ( $pagex - 25 );
                for my $pnum ( 1 .. $pagex - 26 ) {
                    $lnum = int( ( $pnum - 1 ) * $average ) + 1 + $line25;
                    if ( $totpages > 999 ) {
                        $number = sprintf '%04s', $pnum + 25;
                    } else {
                        $number = sprintf '%03s', $pnum + 25;
                    }
                    $textwindow->markSet( "Pg$number", "$lnum.0" );
                    $textwindow->markGravity( "Pg$number", 'left' );
                }
                $average =
                  ( $end - int( $linex + .5 ) ) / ( $totpages - $pagex );
                for my $pnum ( 1 .. ( $totpages - $pagex ) ) {
                    $lnum = int( ( $pnum - 1 ) * $average ) + 1 + $linex;
                    if ( $totpages > 999 ) {
                        $number = sprintf '%04s', $pnum + $pagex;
                    } else {
                        $number = sprintf '%03s', $pnum + $pagex;
                    }
                    $textwindow->markSet( "Pg$number", "$lnum.0" );
                    $textwindow->markGravity( "Pg$number", 'left' );
                }
                ::killpopup('guesspgmarkerpop');
            },
            -text  => 'Guess Page #s',
            -width => 18
        )->grid( -row => 1, -column => 1, -padx => 1, -pady => 2 );
        ::initialize_popup_with_deletebinding('guesspgmarkerpop');
    }
    return;
}

#
# Update the list of operations in the operation history dialog
sub oppopupdate {
    my $href = shift;
    $::lglobal{oplistbox}->delete( '0', 'end' );

    # Sort operations by date/time completed
    foreach my $value (
        sort { $::operationshash{$a} cmp $::operationshash{$b} }
        keys %::operationshash
    ) {
        $::lglobal{oplistbox}->insert( 'end', "$value $::operationshash{$value}" );
    }
    $::lglobal{oplistbox}->update;
}

#
# Add an operation to the list of operations
sub operationadd {
    return unless $::trackoperations;
    my $operation = shift;
    my ( $sec, $min, $hour, $mday, $mon, $year ) = localtime(time);
    $year += 1900;
    $mon  += 1;
    my $timestamp = sprintf( '%4d-%02d-%02d %02d:%02d', $year, $mon, $mday, $hour, $min );
    $::operationshash{$operation} = $timestamp;
    ::oppopupdate() if $::lglobal{oppop};
    ::setedited(1);
}

#
# Pop up an "Operation" history. Track which functions have already been
# run.
sub opspop_up {
    my $top = $::top;
    if ( $::lglobal{oppop} ) {
        $::lglobal{oppop}->deiconify;
        $::lglobal{oppop}->raise;
    } else {
        $::lglobal{oppop} = $top->Toplevel;
        $::lglobal{oppop}->title('Operations history');
        $::lglobal{oppop}->Label(
            -text => ( $::trackoperations ? '' : "Tracking operations is currently DISABLED.\n" )
              . "Note that the Operations History usually records when an activity is started,\n"
              . "and does not guarantee that it has been completed." )
          ->pack( -side => 'top', -padx => 5, -pady => 2 );
        my $frame = $::lglobal{oppop}->Frame->pack(
            -anchor => 'nw',
            -fill   => 'both',
            -expand => 'both',
            -padx   => 2,
            -pady   => 2
        );
        $::lglobal{oplistbox} = $frame->Scrolled(
            'Listbox',
            -scrollbars  => 'se',
            -background  => $::bkgcolor,
            -selectmode  => 'single',
            -activestyle => 'none',
        )->pack(
            -anchor => 'nw',
            -fill   => 'both',
            -expand => 'both',
            -padx   => 2,
            -pady   => 2
        );
        ::drag( $::lglobal{oplistbox} );
        ::initialize_popup_with_deletebinding('oppop');
    }
    ::oppopupdate();
}

#
# If file has been edited, ask user if they want to save the edits
#
# If user cancels, sub returns "C/cancel", i.e. continue without saving or discarding
# If user answers "Yes", sub returns "no"(!) after saving the file
# If user answers "No", sub returns "N/no", and any changes are lost
# Note need to compare return value case-insensitively
# Typically called prior to quit/close/load operation - return matching /no/i means ok to continue that operation
sub confirmdiscard {
    my $textwindow = $::textwindow;
    my $top        = $::top;
    if ( ::isedited() ) {
        my $ans = $top->messageBox(
            -icon    => 'warning',
            -type    => 'YesNoCancel',
            -default => 'yes',
            -title   => 'Save file?',
            -message => 'The file has been modified without being saved. Save edits?'
        );
        if ( $ans =~ /yes/i ) {
            savefile();
        } else {
            return $ans;
        }
    }
    return 'no';
}

#
# Clear the current file if user is ok to discard any unsaved edits
# See sub confirmdiscard for description of return value
sub confirmempty {
    my $textwindow = $::textwindow;
    my $answer     = confirmdiscard();
    if ( $answer =~ /no/i ) {
        clearpopups();
        $textwindow->EmptyDocument;
        ::setedited(0);
    }
    return $answer;
}

#
# Open a file - a main project file, normally text or HTML
sub openfile {
    my $name       = shift;
    my $top        = $::top;
    my $textwindow = $::textwindow;
    return if ( $name eq '*empty*' );
    return if ( ::confirmempty() =~ /cancel/i );
    return if bad_filename_chars($name);
    unless ( -e $name ) {
        my $dbox = $top->Dialog(
            -text    => 'Could not find file. Perhaps it has been moved or deleted.',
            -bitmap  => 'error',
            -title   => 'File not found',
            -buttons => ['Ok']
        );
        $dbox->Show;
        return;
    }
    clearvars($textwindow);
    clearpopups();
    my ( $fname, $extension, $filevar );
    $textwindow->Load($name);
    ( $fname, $::globallastpath, $extension ) = ::fileparse($name);
    $textwindow->markSet( 'insert', '1.0' );
    $::globallastpath           = ::os_normal($::globallastpath);
    $name                       = ::os_normal($name);
    $::lglobal{global_filename} = $name;
    $::projectid                = '';                               # Clear project id from previous file - get new one later
    my $binname = getbinname();

    unless ( -e $binname ) {                                        #for backward compatibility
        $binname = $::lglobal{global_filename};
        $binname =~ s/\.[^\.]*$/\.bin/;
        if ( $binname eq $::lglobal{global_filename} ) { $binname .= '.bin' }
    }
    if ( -e $binname ) {
        ::dofile($binname);                                         #do $binname;
        interpretbinfile();
    } else {
        print "No bin file found, generating default bin file.\n";
    }

    # If no bin file, or bin file didn't have a project id,
    # try to get one from the local project comments filename.
    ::getprojectid() unless $::projectid;
    recentupdate($name);
    unless ( -e $::pngspath ) {
        $::pngspath = $::globallastpath . $::defaultpngspath;
        unless ( -e $::pngspath ) {
            $::pngspath = $::globallastpath . ::os_normal( $::projectid . '_images/' )
              if $::projectid;
        }
        unless ( -e $::pngspath ) {
            $::pngspath = '';
        }
    }
    ::highlight_scannos();
    ::highlight_quotbrac();
    file_mark_pages() if $::auto_page_marks;
    ::readlabels();

    ::operationadd("Open $::lglobal{global_filename}");
    ::setedited(0);
    ::savesettings();
    ::reset_autosave();
}

#
# Return true if filename contains invalid characters - currently allows only printable ASCII.
# On failure, pops a dialog to warn the user.
sub bad_filename_chars {
    my $name = shift;
    return 0 if not $name or $name !~ /[^\x20-\x7F]/;
    $::top->Dialog(
        -text    => 'Only ASCII characters are permitted in filenames.',
        -bitmap  => 'error',
        -title   => 'Invalid filename characters',
        -buttons => ['Ok']
    )->Show;
    return 1;
}

#
# Load settings from setting.rc file which should be valid perl
sub readsettings {
    return if $::lglobal{runtests};    # don't want tests to be affected by a saved setting.rc file

    # Should be able to "do" the file if it exists
    if ( -e ::path_settings() ) {
        my $result = ::dofile( ::path_settings() );

        # If that fails, try to read the file and "eval" the contents
        unless ( $result and $result == 1 ) {
            open my $file, "<", ::path_settings() or die "Could not open setting file\n";
            my @file = <$file>;
            close $file;
            my $settings = '';
            $settings .= $_ for @file;
            $result = eval($settings);

            # If that fails, copy so user can inspect it since setting.rc will be overwritten
            unless ( $result and $result == 1 ) {
                warn "Copying corrupt setting.rc to setting.err\n";
                open $file, ">", ::catfile( $::lglobal{homedirectory}, 'setting.err' );
                print $file @file;
                close $file;
            }
        }
    }

    # If someone just upgraded, reset the update counter
    unless ( $::lastversionrun eq $::VERSION ) {
        $::lastversioncheck = time();
        $::lastversionrun   = $::VERSION;

        $::lmargin = 0 if ( $::lmargin == 1 );

        # for dialogs that previously just stored position but now need geometry,
        # retain the position and delete the position hash entry
        for ( 'gotolabpop', 'gotolinepop', 'gotopagpop', 'grpop', 'searchpop', 'htmlimpop' ) {
            if ( $::positionhash{$_} and $::geometryhash{$_} ) {
                $::geometryhash{$_} =~ s/^(\d+x\d+).*/$1$::positionhash{$_}/;
                delete $::positionhash{$_};
            }
        }

        # get rid of geometry values that are out of use, but keep the position
        for ( keys %::geometryhash ) {
            if ( $::positionhash{$_} ) {
                if ( $::geometryhash{$_} =~ m/^\d+x\d+(\+\d+\+\d+)$/ ) {
                    $::positionhash{$_} = $1;
                }
                delete $::geometryhash{$_};
            }
        }

        # force the first element of extops to be "view in browser"
        if (   $::extops[0]{label} eq 'Open current file in its default program'
            || $::extops[0]{label} eq 'Pass open file to default handler' ) {
            $::extops[0]{label} = 'View in browser';
        }
    }

    # Always force 'View in browser' to be the first entry as other parts
    # of the code assume this
    if ( $::extops[0]{label} =~ m/browser/ ) {
        $::extops[0]{label} = 'View in browser';
    } else {
        unshift(
            @::extops,
            {
                'label'   => 'View in browser',
                'command' => $::globalbrowserstart . ' "$d$f$e"',
            }
        );
    }

    # Correct previous bug which stored bad value in $::ignoreversions
    $::ignoreversions = "revisions" if $::ignoreversions eq "revision";
}

#
# Save setting.rc file
sub savesettings {
    return if $::lglobal{runtests};    # don't want setting.rc file to be overwritten during tests

    my $top = $::top;

    #print time()."savesettings\n";
    my $message = <<EOM;
# This file contains your saved settings for guiguts.
# It is automatically generated when you save your settings.
# If you delete it, all the settings will revert to defaults.
# You shouldn't ever have to edit this file manually.\n\n
EOM
    my ( $index, $savethis );

    #my $thispath = $0;
    #$thispath =~ s/[^\\]*$//;
    my $savefile = ::path_settings();
    $::geometry = $top->geometry unless $::geometry;
    if ( open my $save_handle, '>', $savefile ) {
        print $save_handle $message;

        # a variable's value is also saved if it is zero
        # otherwise we can't have a default value of 1 without overwriting the user's setting
        for (
            qw/alpha_sort activecolor auto_page_marks auto_show_images autobackup autosave autosaveinterval bkgcolor
            blocklmargin blockrmargin bold_char charsuitewfhighlight composepopbinding cssvalidationlevel
            defaultindent donotcenterpagemarkers epubpercentoverride failedsearch
            font_char fontname fontsize fontweight gblfontname gblfontsize gblfontweight gblfontsystemuse
            geometry gesperrt_char globalaspellmode highlightcolor history_size xmlserialization
            htmlimageallowpixels htmlimagewidthtype ignoreversionnumber
            intelligentWF ignoreversions italic_char jeebiesmode lastversioncheck lastversionrun
            lmargin longordlabel markupthreshold
            multisearchsize multiterm nobell nohighlights pagesepauto notoolbar poetrylmargin
            recentfile_size rmargin rmargindiff rwhyphenspace sc_char scannos_highlighted
            searchstickyoptions spellcheckwithenchant spellquerythreshold srstayontop stayontop toolside
            trackoperations txt_conv_bold txt_conv_font txt_conv_gesperrt txt_conv_italic txt_conv_sc txt_conv_tb
            txtfontname txtfontsize txtfontweight txtfontsystemuse
            twowordsinhyphencheck utfcharentrybase utffontname utffontsize utffontweight
            urlprojectpage urlprojectdiscussion
            verboseerrorchecks viscolnm vislnnm wfstayontop/
        ) {
            print $save_handle "\$$_", ' ' x ( 25 - length $_ ), "= '", eval '$::' . $_, "';\n";
        }
        print $save_handle "\n";
        for (
            qw /globallastpath globalspellpath globalspelldictopt globalviewerpath
            globalbrowserstart gutcommand jeebiescommand scannospath tidycommand
            validatecommand validatecsscommand epubcheckcommand ebookmakercommand/
        ) {
            if ( eval '$::' . $_ ) {
                print $save_handle "\$$_", ' ' x ( 20 - length $_ ), "= '",
                  ::escape_problems( ::os_normal( eval '$::' . $_ ) ), "';\n";
            }
        }
        print $save_handle ("\n\@recentfile = (\n");
        for (@::recentfile) {
            print $save_handle "\t'", ::escape_problems($_), "',\n";
        }
        print $save_handle (");\n\n");
        print $save_handle ("\@extops = (\n");
        for my $index ( 0 .. $#::extops ) {
            my $label   = ::escape_problems( $::extops[$index]{label} )   || '';
            my $command = ::escape_problems( $::extops[$index]{command} ) || '';
            print $save_handle "\t{'label' => '$label', 'command' => '$command'},\n";
        }
        print $save_handle ");\n\n";

        for ( keys %::geometryhash ) {
            print $save_handle "\$geometryhash{$_}", ' ' x ( 18 - length $_ ),
              "= '$::geometryhash{$_}';\n";
        }
        print $save_handle "\n";
        for ( keys %::positionhash ) {
            print $save_handle "\$positionhash{$_}", ' ' x ( 18 - length $_ ),
              "= '$::positionhash{$_}';\n";
        }
        print $save_handle "\n";

        print $save_handle '@fixopts = (';
        for (@::fixopts) { print $save_handle "$_," }
        print $save_handle ");\n\n";

        print $save_handle '@mygcview = (';
        for (@::mygcview) { print $save_handle "$_," }
        print $save_handle (");\n\n");

        print $save_handle ("\@quicksearch_history = (\n");
        my @array = @::quicksearch_history;
        for my $index (@array) {
            $index = ::escapeforperlstring($index);
            print $save_handle qq/\t"$index",\n/;
        }
        print $save_handle ");\n\n";

        print $save_handle ("\@search_history = (\n");
        @array = @::search_history;
        for my $index (@array) {
            $index = ::escapeforperlstring($index);
            print $save_handle qq/\t"$index",\n/;
        }
        print $save_handle ");\n\n";

        print $save_handle ("\@replace_history = (\n");
        @array = @::replace_history;
        for my $index (@array) {
            $index = ::escapeforperlstring($index);
            print $save_handle qq/\t"$index",\n/;
        }
        print $save_handle ");\n\n";

        print $save_handle ("\@multidicts = (\n");
        for my $index (@::multidicts) {
            print $save_handle qq/\t"$index",\n/;
        }
        print $save_handle ");\n\n";

        print $save_handle ("\@userchars = (\n");
        for (@::userchars) {
            my $hstr = ( $_ ? '\x{' . ( sprintf "%x", ord($_) ) . '}' : ' ' );
            print $save_handle "\t\"", $hstr, "\",\n";
        }
        print $save_handle ");\n\n";

        print $save_handle ("\@htmlentry = (\n");
        for (@::htmlentry) {
            print $save_handle "\t'", ::escape_problems($_), "',\n";
        }
        print $save_handle ");\n\n";

        print $save_handle ("\@htmlentryhistory = (\n");
        for (@::htmlentryhistory) {
            print $save_handle "\t'", ::escape_problems($_), "',\n";
        }
        print $save_handle ");\n\n";

        for ( keys %::htmlentryattribhash ) {
            my $val = ::escape_problems( $::htmlentryattribhash{$_} );
            print $save_handle "\$htmlentryattribhash{$_}", ' ' x ( 8 - length $_ ), "= '$val';\n";
        }
        print $save_handle "\n\n";

        # Final line
        print $save_handle "1;\n";
    }
}

#
# Return the name of the bin file associated with the currently loaded file
sub getbinname {
    my $binname = "$::lglobal{global_filename}.bin";
    unless ( -e $binname ) {    #for backward compatibility
        $binname = $::lglobal{global_filename};
        $binname =~ s/\.[^\.]*$/\.bin/;
        if ( $binname eq $::lglobal{global_filename} ) { $binname .= '.bin' }
    }
    return $binname;
}

#
# Export a single file with page break location information appended
sub file_export_pagemarkup {
    my $textwindow = $::textwindow;
    my ($name);
    ::savefile() if ( $textwindow->numberChanges );
    $name = $textwindow->getSaveFile(
        -title      => 'Export with Page Markers',
        -initialdir => getsafelastpath()
    );
    return unless $name;
    $::lglobal{exportwithmarkup} = 1;
    ::html_convert_pageanchors();
    $::lglobal{exportwithmarkup} = 0;

    if ( defined($name) and length($name) ) {
        $name .= '.gut';
        my $bincontents = '';
        open my $fh, '<', getbinname() or die "Could not read " . getbinname();
        my $inpagenumbers   = 0;
        my $pastpagenumbers = 0;
        while ( my $line = <$fh> ) {
            $bincontents .= $line;
        }
        close $fh;

        # write the file with page markup
        open my $fh2, '>', "$name" or die "Could not write $name";
        my $filecontents = $textwindow->get( '1.0', 'end -1c' );
        utf8::encode($filecontents);
        print $fh2 "##### Do not edit this line. File exported from guiguts #####\n";
        print $fh2 $filecontents;

        # write the bin contents
        print $fh2 "\n";
        print $fh2 "##### Do not edit below. #####\n";
        print $fh2 $bincontents;
        close $fh2;
    }
    openfile( $::lglobal{global_filename} );
}

#
# Import an exported file containing page break location information
sub file_import_markup {
    my $textwindow = $::textwindow;
    return if ( ::confirmempty() =~ /cancel/i );
    my ($name);
    my $types = [ [ '.gut Files', [qw/.gut/] ], [ 'All Files', ['*'] ], ];
    $name = $textwindow->getOpenFile(
        -filetypes  => $types,
        -title      => 'Open File',
        -initialdir => getsafelastpath()
    );
    return unless defined($name) and length($name);
    ::openfile($name);
    $::lglobal{global_filename} = 'No File Loaded';
    $textwindow->FileName( $::lglobal{global_filename} );

    my $firstline = $textwindow->get( '1.0', '1.end' );
    if ( $firstline =~ '##### Do not edit this line.' ) {
        $textwindow->delete( '1.0', '2.0' );
    }
    my $binstart = $textwindow->search( '-exact', '--', '##### Do not edit below.', '1.0', 'end' );
    return unless $binstart;    # File is not an exported .gut file
    my ( $row, $col ) = split( /\./, $binstart );
    $textwindow->delete( "$row.0", "$row.end" );
    my $binfile = $textwindow->get( "$row.0", "end" );
    $textwindow->delete( "$row.0", "end" );
    ::evalstring($binfile);
    my ( $pagenumberstartindex, $pagenumberendindex, $pagemarkup );
    ::working('Converting Page Number Markup');

    while ( $pagenumberstartindex = $textwindow->search( '-regexp', '--', '<Pg', '1.0', 'end' ) ) {
        $pagenumberendindex =
          $textwindow->search( '-regexp', '--', '>', $pagenumberstartindex, 'end' );
        $pagemarkup = $textwindow->get( $pagenumberstartindex . '+1c', $pagenumberendindex );
        $textwindow->delete( $pagenumberstartindex, $pagenumberendindex . '+1c' );
        $::pagenumbers{$pagemarkup}{offset} = $pagenumberstartindex;
    }
    ::working();
    interpretbinfile();    # place page markers with the above offsets
}

{    # Start of block to localise OCR file variables
    my $ocr_pagenum;     # Current page number
    my $ocr_textpage;    # buffer text extracted from current page to improve performance

    # Import Abbyy OCR file from TIA (may be gzipped)
    # Convert it to a simple text file and set the page markers ready for Prep File export
    sub file_import_ocr {
        my $textwindow = $::textwindow;
        return if ( ::confirmempty() =~ /cancel/i );

        my $directory = '';
        my $types     = [ [ 'Gzip Files', ['.gz'] ], [ 'All Files', ['*'] ], ];
        my $name      = $textwindow->getOpenFile(
            -title      => 'Open OCR File',
            -filetypes  => $types,
            -initialdir => getsafelastpath()
        );
        return unless defined($name) and length($name);
        clearvars($textwindow);
        clearpopups();
        ::working('Converting OCR File');
        $ocr_pagenum = 0;

        my $lines_read_ok = 0;
        $ocr_textpage = '';

        # If gzip is not available under Windows, this still creates a valid file handle
        # but no lines will be read successfully
        my $opencmd = ( $name =~ /\.gz$/ ) ? "gzip -cd '$name' |" : "< $name";    # Unzip if it's an Abbyy.gz file
        open( my $fh, $opencmd );

        # Read one line at a time and decode it
        while ( my $line = <$fh> ) {
            $lines_read_ok = 1;
            utf8::decode($line);
            ocrdecodetia($line);

            unless ( ::updatedrecently() ) {    # Update screen occasionally so user can see progress
                $textwindow->see('end');
                $textwindow->update();
            }
        }

        close $fh;
        ocrpageflush();
        $textwindow->see('end');
        $textwindow->update();
        file_mark_pages() if $::auto_page_marks;    # Interpret page separators to find page boundaries
        ::working();

        # give user chance to save combined file - necessary for operations like character count
        if ($lines_read_ok) {
            ::setedited(1);
            file_saveas($textwindow);
        } else {
            my $msg = "Failed to read lines from file.";
            $msg =
                "Failed to read lines from .gz file.\n"
              . "Check 'gzip' command is on your PATH,\n"
              . "or unzip file manually and import again."
              if $name =~ /\.gz$/;
            $::top->Dialog(
                -text    => $msg,
                -bitmap  => 'error',
                -title   => 'File Read Error',
                -buttons => ['Ok']
            )->Show;
        }
    }

    # Decode a line of OCR from TIA
    # Abbyy files have page, paragraph, line and characters marked with XML markup
    sub ocrdecodetia {
        my $line = shift;

        my @strings = split( /<\/[^>]+>/, $line );    # Split long lines at closing tags
        for my $string (@strings) {
            if ( $string =~ /<page / ) {              # New page - output page text and add DP page separator
                ocrpageflush( $ocr_pagenum++ );
            } elsif ( $string =~ /<par / ) {          # New paragraph, so need extra newline
                $ocr_textpage .= "\n";
            } elsif ( $string =~ /<line / ) {         # New line
                $ocr_textpage .= "\n";
                if ( $string =~ /<charParams.*>([^<]+)$/ ) {    # Character can appear straight after <line>
                    $ocr_textpage .= $1;
                }
            } elsif ( $string =~ /<charParams.*>([^<]+)$/ ) {    # Character
                $ocr_textpage .= $1;
            }
        }
    }

    # Flush page buffer to screen and set up new page header
    sub ocrpageflush {
        my $textwindow = $::textwindow;
        my $newpagenum = shift;
        $newpagenum = 99999 unless defined $newpagenum;    # Final flush at end, new page separator will never get output

        $ocr_textpage =~ s/&amp;/&/g;                      # Translate entities
        $ocr_textpage =~ s/&lt;/</g;
        $ocr_textpage =~ s/&gt;/>/g;
        $ocr_textpage =~ s/&apos;/'/g;
        $ocr_textpage =~ s/&quot;/"/g;
        $ocr_textpage =~ s/ +\n/\n/g;                      # Remove trailing spaces on lines
        $ocr_textpage =~ s/ +$//g;                         # Remove trailing spaces at end of page
        $ocr_textpage =~ s/  +/ /g;                        # Compress multiple spaces to one
        $ocr_textpage =~ s/\n\n+/\n\n/g;                   # Compress multiple blank lines to one
        $ocr_textpage =~ s/\n+$//g;                        # Remove trailing blank lines

        $textwindow->ntinsert( 'end', "$ocr_textpage" );
        $ocr_textpage = sprintf "\n-----File: %05d.png---", $newpagenum;    # Start of next page
    }
}

#
# Set up page marks, bookmarks, etc. after loading a bin file
sub interpretbinfile {
    my $textwindow = $::textwindow;
    my $markindex;
    foreach my $mark ( sort keys %::pagenumbers ) {
        $markindex = $::pagenumbers{$mark}{offset};
        unless ($markindex) {
            delete $::pagenumbers{$mark};
            next;
        }
        $textwindow->markSet( $mark, $markindex );
        $textwindow->markGravity( $mark, 'left' );
    }
    for ( 1 .. 5 ) {
        if ( $::bookmarks[$_] ) {
            $textwindow->markSet( 'insert', $::bookmarks[$_] );
            $textwindow->markSet( "bkmk$_", $::bookmarks[$_] );
            ::setbookmark($_);
        }
    }
    ::setedited(0);
    $::bookmarks[0] ||= '1.0';
    $textwindow->markSet( 'insert',    $::bookmarks[0] );
    $textwindow->markSet( 'spellbkmk', $::spellindexbkmrk )
      if $::spellindexbkmrk;
    $textwindow->see( $::bookmarks[0] );
    $textwindow->focus;
    return ();
}

#
# Returns true if file has been edited since last save
sub isedited {
    my $textwindow = $::textwindow;
    return $textwindow->numberChanges || $::lglobal{isedited};
}

#
# Set the "edited" flag
# Pass a non-zero value to mark file as needing to be saved
# Pass zero to clear flag after file has been saved
# Note that clearing the flag also clears the Undo list, i.e.
# once a file has been saved, it is not possible to undo before that point
sub setedited {
    my $val        = shift;
    my $textwindow = $::textwindow;
    $::lglobal{isedited} = $val;
    $textwindow->ResetUndo unless $val;
}

#
# Pop the Enable Character Suites dialog
sub charsuitespopup {
    my $top = $::top;
    if ( defined( $::lglobal{charsuitespopup} ) ) {
        $::lglobal{charsuitespopup}->deiconify;
        $::lglobal{charsuitespopup}->raise;
        $::lglobal{charsuitespopup}->focus;
    } else {
        $::lglobal{charsuitespopup} = $top->Toplevel;
        $::lglobal{charsuitespopup}->title('Enabled Character Suites');
        ::initialize_popup_with_deletebinding('charsuitespopup');

        # Create a checkbutton for each character suite
        my $f0  = $::lglobal{charsuitespopup}->Frame->pack;
        my $row = 1;
        for my $suite ( sort keys %{ $::lglobal{dpcharsuite} } ) {
            $::charsuiteenabled{$suite} = 0 unless defined $::charsuiteenabled{$suite};
            $f0->Checkbutton(
                -variable => \$::charsuiteenabled{$suite},
                -text     => $suite,
                -state    => ( $suite eq 'Basic Latin' ? 'disabled' : 'normal' ),    # User can't turn off Basic Latin
                -command  => sub { ::sortanddisplayhighlight(); },
            )->grid(
                -row    => $row++,
                -column => 1,
                -sticky => 'w'
            );
        }

        $::lglobal{charsuitespopup}->resizable( 'yes', 'yes' );
        $::lglobal{charsuitespopup}->raise;
        $::lglobal{charsuitespopup}->focus;
    }
}

#
# Check if given character is in an enabled character suite
sub charsuitecheck {
    my $char = shift;
    for my $suite ( keys %{ $::lglobal{dpcharsuite} } ) {
        next unless $::charsuiteenabled{$suite};    # Only check enabled suites
        return 1 if index( $::lglobal{dpcharsuite}{$suite}, $char ) >= 0;
    }
    return 0;
}

#
# Return which character suite contains given character (or empty string if none)
sub charsuitefind {
    my $char = shift;
    for my $suite ( sort keys %{ $::lglobal{dpcharsuite} } ) {    # Check suites in alphabetical order
        return $suite if index( $::lglobal{dpcharsuite}{$suite}, $char ) >= 0;
    }
    return '';
}

#
# Enable the given character suite
sub charsuiteenable {
    my $suite = shift;
    $::charsuiteenabled{$suite} = 1;
}

#
# Does several global substitutions required by Content Providers
sub cpcharactersubs {
    my $textwindow = $::textwindow;
    $textwindow->addGlobStart;
    $textwindow->FindAndReplaceAll( '-exact', '-nocase', "\x{0009}", " " );     # tab --> space
    $textwindow->FindAndReplaceAll( '-exact', '-nocase', "\x{2014}", "--" );    # emdash --> double hyphen
    $textwindow->FindAndReplaceAll( '-exact', '-nocase', "\x{2018}", "'" );     # left single quote --> straight
    $textwindow->FindAndReplaceAll( '-exact', '-nocase', "\x{2019}", "'" );     # right single quote --> straight
    $textwindow->FindAndReplaceAll( '-exact', '-nocase', "\x{201c}", "\"" );    # left double quote --> straight
    $textwindow->FindAndReplaceAll( '-exact', '-nocase', "\x{201d}", "\"" );    # right double quote --> straight
    $textwindow->addGlobEnd;
}

#
# Return the last-accessed directory ($::globallastpath) unless it has
# been deleted, in which case return the directory containing guiguts.pl
# On Macs (maybe also Linux) attempting to open a File Selection Dialog
# on a deleted folder gives an error.
sub getsafelastpath {
    if ( -d $::globallastpath ) {
        return $::globallastpath;
    } else {
        return $::lglobal{guigutsdirectory};
    }
}

1;
