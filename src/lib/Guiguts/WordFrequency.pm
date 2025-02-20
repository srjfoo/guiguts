package Guiguts::WordFrequency;
use strict;
use warnings;

BEGIN {
    use Exporter();
    our ( @ISA, @EXPORT );
    @ISA    = qw(Exporter);
    @EXPORT = qw(&wordfrequencybuildwordlist &wordfrequency &ital_adjust &sortanddisplayhighlight);
}

#
# Build lists of words, word pairs, and double hyphenated words
sub wordfrequencybuildwordlist {
    my $textwindow = shift;
    my ( @words, $match );
    my $wc = 0;
    $::lglobal{seenwordsdoublehyphen} = ();
    $::lglobal{seenwords}             = ();
    $::lglobal{seenwordpairs}         = ();
    my $lastwordseen = '';

    my $index = '1';
    while ( $textwindow->compare( "$index.0", '<', 'end' ) ) {
        my $line = $textwindow->get( "$index.0", "$index.end" );
        ++$index;
        next if $line =~ m/^-----*\s?File:\s?\S+\.(png|jpg)---/;
        $line         =~ s/_/ /g;
        $line         =~ s/<!--//g;
        $line         =~ s/-->//g;
        $line         =~ s/<\/?[a-z]*>/ /g;                        # throw away tags
        if ( $::lglobal{wf_ignore_case} ) { $line = lc($line) }
        @words = split( /\s+/, $line );

        # build a list of "word--word""
        for my $word (@words) {
            next unless ( $word =~ /[^-]--[^-]/ );
            next if ( $word =~ /---/ );
            $word =~ s/[\.,']$//;
            $word =~ s/^[\.'-]+//;
            next if ( $word eq '' );
            $match = ( $::lglobal{wf_ignore_case} ) ? lc($word) : $word;
            $::lglobal{seenwordsdoublehyphen}->{$match}++;
        }
        $line =~ s/[^'\.,\p{Alnum}\p{Mark}\*-]/ /g;    # get rid of nonalphanumeric (retaining combining characters)
        $line =~ s/--/ /g;                             # get rid of --
        $line =~ s/�/ /g;                              # trying to catch words with real em-dashes, from dp2rst
        $line =~ s/(\D),/$1 /g;                        # throw away comma after non-digit
        $line =~ s/,(\D)/ $1/g;                        # and before
        @words = split( /\s+/, $line );
        for my $word (@words) {
            $word =~ s/ //g;
            if ( length($word) == 0 ) { next; }
            if ( $lastwordseen && not( "$lastwordseen $word" =~ m/\d/ ) ) {
                $::lglobal{seenwordpairs}->{"$lastwordseen $word"}++;
            }
            $lastwordseen = $word;
            $word =~ s/(?<!\-)\*//g;
            $word =~ s/^\*$//;
            $word =~ s/[\.	',-]+$//;    # throw away punctuation at end
            $word =~ s/^[\.,'-]+//;     #and at the beginning
            next if ( $word eq '' );
            $wc++;
            $match = ( $::lglobal{wf_ignore_case} ) ? lc($word) : $word;
            $::lglobal{seenwords}->{$match}++;
        }
    }
    return $wc;
}

#
# Pop the Word Frequency dialog
sub wordfrequency {
    my $top        = $::top;
    my $textwindow = $::textwindow;
    ::operationadd('Word Frequency');
    ::hidepagenums();
    ::oppopupdate() if $::lglobal{oppop};
    my ( @words, $match, @savesets );
    my $index = '1.0';
    my $wc    = 0;
    my $end   = $textwindow->index('end');

    if ( $::lglobal{wfpop} ) {
        $::lglobal{wfpop}->deiconify;
        $::lglobal{wfpop}->raise;
        $::lglobal{wclistbox}->delete( '0', 'end' );
    } else {
        $::lglobal{wfpop} = $top->Toplevel;
        $::lglobal{wfpop}->title('Word Frequency');
        my $wordfreqseframe = $::lglobal{wfpop}->Frame->pack( -side => 'top', -anchor => 'n' );
        my $wcopt3          = $wordfreqseframe->Checkbutton(
            -variable => \$::lglobal{suspects_only},
            -text     => 'Suspects only'
        )->pack( -side => 'left', -anchor => 'w', -pady => 1 );
        my $wcopt1 = $wordfreqseframe->Checkbutton(
            -variable => \$::lglobal{wf_ignore_case},
            -text     => 'Ignore case',
        )->pack( -side => 'left', -anchor => 'w', -pady => 1 );
        $wordfreqseframe->Radiobutton(
            -variable => \$::alpha_sort,
            -value    => 'a',
            -text     => 'Alph',
        )->pack( -side => 'left', -anchor => 'w', -pady => 1 );
        $wordfreqseframe->Radiobutton(
            -variable => \$::alpha_sort,
            -value    => 'f',
            -text     => 'Frq',
        )->pack( -side => 'left', -anchor => 'w', -pady => 1 );
        $wordfreqseframe->Radiobutton(
            -variable => \$::alpha_sort,
            -value    => 'l',
            -text     => 'Len',
        )->pack( -side => 'left', -anchor => 'w', -pady => 1 );
        $wordfreqseframe->Button(
            -command => sub {
                return unless ( $::lglobal{wclistbox}->curselection );
                $::lglobal{harmonics} = 1;
                harmonicspop();
            },
            -text => '1st Harm',
        )->pack(
            -side   => 'left',
            -padx   => 1,
            -pady   => 1,
            -anchor => 'w'
        );
        $wordfreqseframe->Button(
            -command => sub {
                return unless ( $::lglobal{wclistbox}->curselection );
                $::lglobal{harmonics} = 2;
                harmonicspop();
            },
            -text => '2nd Harm',
        )->pack(
            -side   => 'left',
            -padx   => 1,
            -pady   => 1,
            -anchor => 'w'
        );
        $wordfreqseframe->Button(
            -command => sub {

                #return if $::lglobal{global_filename} =~ /No File Loaded/;
                #savefile() unless ( $textwindow->numberChanges == 0 );
                wordfrequency();
            },
            -text => 'Rerun '
        )->pack(
            -side   => 'left',
            -padx   => 2,
            -pady   => 1,
            -anchor => 'w'
        );
        my $wordfreqseframe1 = $::lglobal{wfpop}->Frame->pack( -side => 'top', -anchor => 'n' );
        my @wfbuttons        = (
            [ 'Emdashes'  => sub { dashcheck() } ],
            [ 'Hyphens'   => sub { hyphencheck() } ],
            [ 'Alpha/num' => sub { alphanumcheck() } ],
            [ 'All Words' => sub { allwords($wc) } ],
            [ 'Check Spelling',   sub { wordfrequencyspellcheck() } ],
            [ 'Ital/Bold/SC/etc', sub { itwords(); ital_adjust() } ],
            [ 'ALL CAPS',         sub { capscheck() } ],
            [ 'MiXeD CasE',       sub { mixedcasecheck() } ],
            [
                'Initial Caps',
                sub {
                    $::lglobal{wf_ignore_case} = 0;
                    anythingwfcheck( 'words with initial caps', '^\p{Upper}\P{Upper}+$', $top );
                }
            ],
            [ 'Character Cnts', sub { charsortcheck() } ],
            [ 'Check , Upper',  sub { commark() } ],
            [ 'Check . lower',  sub { bangmark() } ],
            [ 'Check Accents',  sub { accentcheck() } ],
            [
                'Unicode > FF',
                [ \&anythingwfcheck, 'words with unicode chars > FF', '[\x{100}-\x{FFEF}]' ]
            ],
            [ 'Stealtho Check', sub { stealthcheck() } ],
            [ 'Ligatures',      sub { ligaturecheck() } ],
            [
                'RegExp-->',
                [
                    sub {
                        anythingwfcheck( 'words matching regular expression', $::regexpentry );
                    }
                ]
            ],
            [ 'RegExpEntry', [ \&anythingwfcheck, 'dummy entry', 'dummy' ] ],
        );
        my ( $row, $col, $inc ) = ( 0, 0, 0 );
        for (@wfbuttons) {
            $row = int( $inc / 5 );
            $col = $inc % 5;
            ++$inc;
            if ( not( $_->[0] eq 'RegExpEntry' ) ) {
                my $button = $wordfreqseframe1->Button(
                    -command => $_->[1],
                    -text    => $_->[0],
                    -width   => 13
                )->grid(
                    -row    => $row,
                    -column => $col,
                    -padx   => 1,
                    -pady   => 1
                );
                $button->bind( '<3>' => $_->[2] ) if $_->[2];
            } else {
                $::lglobal{regexpentry} =
                  $wordfreqseframe1->Entry( -textvariable => \$::regexpentry, )->grid(
                    -row        => $row,
                    -column     => $col,
                    -columnspan => 3,
                    -sticky     => "nsew"
                  );
            }
        }
        my $wcframe = $::lglobal{wfpop}->Frame->pack( -fill => 'both', -expand => 'both', );
        $::lglobal{wclistbox} = $wcframe->Scrolled(
            'Listbox',
            -scrollbars  => 'se',
            -background  => $::bkgcolor,
            -font        => 'proofing',
            -selectmode  => 'single',
            -activestyle => 'none',
        )->pack(
            -anchor => 'nw',
            -fill   => 'both',
            -expand => 'both',
            -padx   => 2,
            -pady   => 2
        );
        my $helpframe = $::lglobal{wfpop}->Frame->pack( -side => 'bottom' );
        $helpframe->Label( -text => 'Double-click a line to find in text, Right-click to open S&R' )
          ->pack;
        $helpframe->Label(
            -text => 'Type a letter to see it, Ctrl+s to save list, Ctrl+x to export list', )->pack;
        ::initialize_popup_without_deletebinding('wfpop');
        ::drag( $::lglobal{wclistbox} );
        $::lglobal{wfpop}->protocol(
            'WM_DELETE_WINDOW' => sub {
                ::killpopup('wfpop');
                undef $::lglobal{wclistbox};
                $::lglobal{markuppopok}->invoke if $::lglobal{markuppop};
            }
        );
        $::lglobal{wclistbox}->eventAdd( '<<search>>' => '<ButtonRelease-3>' );
        $::lglobal{wclistbox}->bind(
            '<<search>>',
            sub {
                $::lglobal{wclistbox}->selectionClear( 0, 'end' );
                $::lglobal{wclistbox}->selectionSet(
                    $::lglobal{wclistbox}->index(
                            '@'
                          . ( $::lglobal{wclistbox}->pointerx - $::lglobal{wclistbox}->rootx )
                          . ','
                          . ( $::lglobal{wclistbox}->pointery - $::lglobal{wclistbox}->rooty )
                    )
                );

                # right click means popup a search box
                my ($sword) = $::lglobal{wclistbox}->get( $::lglobal{wclistbox}->curselection );
                ::searchpopup();
                ::searchoptset(@::wfsearchopt);
                $sword =~ s/\d+\s+(\S)/$1/;
                $sword =~ s/\s+\*\*\*\*$//;
                if ( $sword =~ /\*space\*/ ) {
                    $sword = ' ';
                    ::searchoptset(qw/0 x x 1/);
                } elsif ( $sword =~ /\*tab\*/ ) {
                    $sword = '\t';
                    ::searchoptset(qw/0 x x 1/);
                } elsif ( $sword =~ /\*newline\*/ ) {
                    $sword = '\n';
                    ::searchoptset(qw/0 x x 1/);
                } elsif ( $sword =~ /\*nbsp\*/ ) {
                    $sword = '\x{A0}';
                    ::searchoptset(qw/0 x x 1/);
                } elsif ( $sword =~ /\W/ ) {
                    $sword =~ s/([^\w\s\\])/\\$1/g;

                    # Force whole word search via regex - can't use \b because underscore is a "word" character in Perl
                    $sword .= '(?![\p{Alnum}\p{Mark}])'
                      if ( ( length $sword gt 1 ) && ( $sword =~ /\w$/ ) );
                    $sword = '(?<![\p{Alnum}\p{Mark}])' . $sword
                      if ( ( length $sword gt 1 ) && ( $sword =~ /^\w/ ) );
                    ::searchoptset(qw/0 x x 1/);
                }
                $::lglobal{searchentry}->delete( 0, 'end' );
                $::lglobal{searchentry}->insert( 'end', $sword );
                ::updatesearchlabels();
                $::lglobal{searchentry}->after( $::lglobal{delay} );
                $::lglobal{searchpop}->deiconify;
                $::lglobal{searchpop}->raise;
                $::lglobal{searchpop}->focus;
            }
        );
        $::lglobal{wclistbox}->eventAdd( '<<find>>' => '<Double-Button-1>', '<Return>' );
        $::lglobal{wclistbox}->bind(
            '<<find>>',
            sub {
                my ($sword) = $::lglobal{wclistbox}->get( $::lglobal{wclistbox}->curselection );
                return unless length $sword;
                @savesets = @::sopt;
                ::searchoptset(@::wfsearchopt);
                if ( $::lglobal{wf_ignore_case} ) {
                    ::searchoptset(qw/x 1 0 x/);
                } else {
                    ::searchoptset(qw/x 0 0 x/);
                }
                $sword =~ s/(\d+)\s+(\S)/$2/;
                my $snum = $1;
                $sword = '\\\\' if ( $sword eq '\\' );    # special case of backslash in character count
                $sword =~ s/\s+\*\*\*\*$//;
                if ( $sword =~ /\W/ ) {
                    $sword =~ s/\*nbsp\*/\x{A0}/;
                    $sword =~ s/\*tab\*/\t/;
                    $sword =~ s/\*newline\*/\n/;
                    $sword =~ s/\*space\*/ /;
                    $sword =~ s/([^\w\s\\])/\\$1/g;

                    # Force whole word search via regex - can't use \b because underscore is a "word" character in Perl
                    $sword .= '(?![\p{Alnum}\p{Mark}])'
                      if ( ( length $sword gt 1 ) && ( $sword =~ /\w$/ ) );
                    $sword = '(?<![\p{Alnum}\p{Mark}])' . $sword
                      if ( ( length $sword gt 1 ) && ( $sword =~ /^\w/ ) );
                    ::searchoptset(qw/0 0 x 1/);    # Case sensitive
                }

                if ( $::intelligentWF && $sword =~ /^\\,(\s|\\n)/ ) {

                    # during comma-Upper ck, ignore if name followed by period, !, or ?
                    # NOTE: sword will be used as a regular expression filter during display
                    $sword .= '([^\.\?\!]|$)';
                }
                if     ( $sword =~ /\*space\*/ )   { $sword = ' ' }
                elsif  ( $sword =~ /\*tab\*/ )     { $sword = "\t" }
                elsif  ( $sword =~ /\*newline\*/ ) { $sword = "\n" }
                elsif  ( $sword =~ /\*nbsp\*/ )    { $sword = "\xA0" }
                unless ($snum) {
                    ::searchoptset(qw/0 x x 1/);
                    unless ( $sword =~ m/--/ ) {
                        $sword = "(?<=-)$sword|$sword(?=-)";
                    }
                }

                ::searchoptset(qw/x x x x 1/) if $sword ne $::lglobal{wflastsearchterm};
                ::searchtext($sword);
                ::searchoptset(@savesets);
                $::lglobal{wflastsearchterm} = $sword;
                $top->raise;
            }
        );

        # If showing character counts, Ctrl-Mouse-1 allows containing character suite to be selected
        # For other displays, Ctrl-Mouse-1 pops the harmonics dialog
        $::lglobal{wclistbox}->bind(
            '<Control-ButtonRelease-1>',
            sub {
                my $line = $::lglobal{wclistbox}->get('active');
                return unless $line;
                if ( $::lglobal{wfsaveheader} =~ /characters in the file/ ) {
                    charsortsuitecontrol($line) if $::charsuitewfhighlight;
                } else {
                    harmonics($line);
                    harmonicspop();
                }
            }
        );
        add_navigation_events( $::lglobal{wclistbox} );
        $::lglobal{wfpop}->bind(
            '<Control-s>' => sub {
                my ($name);
                $name = $textwindow->getSaveFile(
                    -title       => 'Save Word Frequency List As',
                    -initialdir  => ::getsafelastpath(),
                    -initialfile => 'wordfreq.txt'
                );

                if ( defined($name) and length($name) ) {
                    open( my $save, ">", "$name" );
                    my $list = join "\n", $::lglobal{wclistbox}->get( '0', 'end' );
                    utf8::encode($list);
                    print $save $list;
                }
            }
        );
        $::lglobal{wfpop}->bind(
            '<Control-x>' => sub {
                my ($name);
                $name = $textwindow->getSaveFile(
                    -title       => 'Export Word Frequency List As',
                    -initialdir  => ::getsafelastpath(),
                    -initialfile => 'wordlist.txt'
                );

                if ( defined($name) and length($name) ) {
                    my $count = $::lglobal{wclistbox}->index('end');
                    open( my $save, ">", "$name" );
                    for ( 1 .. $count ) {
                        my $word = $::lglobal{wclistbox}->get($_);
                        if ( ( defined $word ) && ( length $word ) ) {
                            $word =~ s/^\d+\s+//;
                            $word =~ s/\s+\*{4}\s*$//;
                            utf8::encode($word);
                            print $save $word, "\n";
                        }
                    }
                }
            }
        );
    }
    $top->Busy( -recurse => 1 );
    $::lglobal{wclistbox}->focus;
    $::lglobal{wclistbox}->insert( 'end', 'Please wait, building word list....' );
    $wc = wordfrequencybuildwordlist($textwindow);
    allwords($wc);
    $top->Unbusy( -recurse => 1 );
}

#
# Show all words found
sub allwords {
    my $wc = shift;
    $::lglobal{wfsaveheader} =
      "$wc total words. " . keys( %{ $::lglobal{seenwords} } ) . " distinct words in file.";
    sortanddisplaywords( \%{ $::lglobal{seenwords} } );
    @::wfsearchopt = qw/1 x x 0/;
}

#
# Show words with lowercase letter following period
sub bangmark {
    my $top = $::top;
    ::operationadd('Check . lower');
    $top->Busy( -recurse => 1 );
    my %display = ();
    my $wordw   = 0;
    my $ssindex = '1.0';
    my $length  = 0;
    return if ( nofileloaded($top) );
    $::lglobal{wf_ignore_case} = 0;
    $::lglobal{wclistbox}->delete( '0', 'end' );
    $::lglobal{wclistbox}->insert( 'end', 'Please wait, building list....' );
    $::lglobal{wclistbox}->update;
    my $wholefile = $::textwindow->get( '1.0', 'end' );

    while (
        $wholefile =~ m/([\p{Alnum}\p{Mark}]+\.['"]?\n*\s*['"]?\p{Lower}[\p{Alnum}\p{Mark}]*)/g ) {
        my $word = $1;
        $wordw++;
        $word =~ s/\n/\\n/g;
        $display{$word}++;
    }
    $::lglobal{wfsaveheader} = "$wordw words with lower case after period. " . '(\n means newline)';
    sortanddisplaywords( \%display );
    @::wfsearchopt = qw/0 x x 1/;
    $top->Unbusy;
}

#
# Show words with emdashes
sub dashcheck {
    my $top = $::top;
    ::operationadd('Check emdashes');
    $top->Busy( -recurse => 1 );
    $::lglobal{wclistbox}->delete( '0', 'end' );
    $::lglobal{wclistbox}->insert( 'end', 'Please wait, building list....' );
    $::lglobal{wclistbox}->update;
    $::lglobal{wclistbox}->delete( '0', 'end' );
    my $wordw   = 0;
    my $wordwo  = 0;
    my %display = ();

    foreach my $word ( keys %{ $::lglobal{seenwordsdoublehyphen} } ) {
        next if ( $::lglobal{seenwordsdoublehyphen}->{$word} < 1 );
        if ( $word =~ /-/ ) {
            $wordw++;
            my $wordtemp = $word;
            $display{$word} = $::lglobal{seenwordsdoublehyphen}->{$word}
              unless $::lglobal{suspects_only};
            $word =~ s/--/-/g;

            #$word =~ s/�/-/g; # dp2rst creates real em-dashes
            if ( $::lglobal{seenwords}->{$word} ) {
                my $aword = $word . ' ****';
                $display{$wordtemp} = $::lglobal{seenwordsdoublehyphen}->{$wordtemp}
                  if $::lglobal{suspects_only};
                $display{$aword} = $::lglobal{seenwords}->{$word};
                $wordwo++;
            }
        }
    }
    $::lglobal{wfsaveheader} = "$wordw emdash phrases, $wordwo suspects (marked with ****).";
    sortanddisplaywords( \%display );
    @::wfsearchopt = qw/0 x x 0/;
    $top->Unbusy;
}

#
# Show words containing a mix of alphabetic and numeric characters
sub alphanumcheck {
    my $top = $::top;
    ::operationadd('Check alpha/num');
    $top->Busy( -recurse => 1 );
    my %display = ();
    $::lglobal{wclistbox}->delete( '0', 'end' );
    $::lglobal{wclistbox}->insert( 'end', 'Please wait, building word list....' );
    $::lglobal{wclistbox}->update;
    $::lglobal{wclistbox}->delete( '0', 'end' );
    my $wordw = 0;

    foreach ( keys %{ $::lglobal{seenwords} } ) {
        next unless ( $_ =~ /\d/ );
        next unless ( $_ =~ /\p{Alpha}/ );
        $wordw++;
        $display{$_} = $::lglobal{seenwords}->{$_};
    }
    $::lglobal{wfsaveheader} = "$wordw mixed alphanumeric words.";
    sortanddisplaywords( \%display );
    $::lglobal{wclistbox}->update;
    @::wfsearchopt = qw/0 x x 0/;
    $top->Unbusy;
}

#
# Show words that are all caps
sub capscheck {
    my $top = $::top;
    ::operationadd('Check ALL CAPS');
    $top->Busy( -recurse => 1 );
    $::lglobal{wf_ignore_case} = 0;
    $::lglobal{wclistbox}->delete( '0', 'end' );
    $::lglobal{wclistbox}->insert( 'end', 'Please wait, building word list....' );
    $::lglobal{wclistbox}->update;
    my %display = ();
    my $wordw   = 0;

    foreach ( keys %{ $::lglobal{seenwords} } ) {
        next if ( $_ =~ /\p{IsLower}/ );
        if ( $_ =~ /\p{IsUpper}+(?!\p{IsLower})/ ) {
            $wordw++;
            $display{$_} = $::lglobal{seenwords}->{$_};
        }
    }
    $::lglobal{wfsaveheader} = "$wordw distinct capitalized words.";
    sortanddisplaywords( \%display );
    @::wfsearchopt = qw/1 x x 0/;
    $top->Unbusy;
}

#
# Show words that are MiXed CasE
sub mixedcasecheck {
    my $top = $::top;
    ::operationadd('Check MiXeD CasE');
    $top->Busy( -recurse => 1 );
    $::lglobal{wf_ignore_case} = 0;
    $::lglobal{wclistbox}->delete( '0', 'end' );
    $::lglobal{wclistbox}->insert( 'end', 'Please wait, building word list....' );
    $::lglobal{wclistbox}->update;
    my %display = ();
    my $wordw   = 0;

    foreach ( sort ( keys %{ $::lglobal{seenwords} } ) ) {
        next unless ( $_ =~ /\p{IsUpper}/ );
        next unless ( $_ =~ /\p{IsLower}/ );
        next if ( $_ =~ /^\p{Upper}[\p{IsLower}\d'-]+$/ );
        $wordw++;
        $display{$_} = $::lglobal{seenwords}->{$_};
    }
    $::lglobal{wfsaveheader} = "$wordw distinct mixed case words.";
    sortanddisplaywords( \%display );
    @::wfsearchopt = qw/1 x x 0/;
    $top->Unbusy;
}

#
# Handle various word frequency checks - shows words that match the given regex
sub anythingwfcheck {
    my ( $checktype, $checkregexp ) = @_;
    my $top = $::top;
    ::operationadd( 'Check ' . $checktype );
    $::lglobal{wclistbox}->delete( '0', 'end' );
    if ( not ::isvalid($checkregexp) ) {
        $::lglobal{wclistbox}->insert( 'end', "Invalid regular expression: $checkregexp" );
        $::lglobal{wclistbox}->update;
        return;
    }
    $::lglobal{wclistbox}->insert( 'end', 'Please wait, building word list....' );
    $::lglobal{wclistbox}->update;
    $top->Busy( -recurse => 1 );
    my %display = ();
    my $wordw   = 0;
    foreach ( sort ( keys %{ $::lglobal{seenwords} } ) ) {
        next unless ( $_ =~ /$checkregexp/ );
        $wordw++;
        $display{$_} = $::lglobal{seenwords}->{$_};
    }
    $::lglobal{wfsaveheader} = "$wordw distinct $checktype.";
    sortanddisplaywords( \%display );
    @::wfsearchopt = qw/1 x x 0/;
    $top->Unbusy;
}

#
# Check if words appear accented and not-accented but otherwise identical
sub accentcheck {
    my $top = $::top;
    ::operationadd('Check Accents');
    $top->Busy( -recurse => 1 );
    $::lglobal{wclistbox}->delete( '0', 'end' );
    $::lglobal{wclistbox}->insert( 'end', 'Please wait, building word list....' );
    my %display = ();
    my %accent  = ();
    $::lglobal{wclistbox}->update;
    my $wordw  = 0;
    my $wordwo = 0;

    foreach my $word ( keys %{ $::lglobal{seenwords} } ) {
        if ( $word =~ /[\p{Mark}$::convertlatinsinglesearch$::convertcharssinglesearch]/ ) {
            $wordw++;
            my $wordtemp = $word;
            $display{$word} = $::lglobal{seenwords}->{$word}
              unless $::lglobal{suspects_only};
            my @dwords = ( ::deaccentsort($word) );
            if ( $word =~ s/\xC6/Ae/ ) {
                push @dwords, ( ::deaccentsort($word) );
            }
            for my $wordd (@dwords) {
                my $line;
                $line = sprintf( "%-8d %s", $::lglobal{seenwords}->{$wordd}, $wordd )
                  if $::lglobal{seenwords}->{$wordd};
                if ( $::lglobal{seenwords}->{$wordd} ) {
                    $display{$wordtemp} = $::lglobal{seenwords}->{$wordtemp}
                      if $::lglobal{suspects_only};
                    $display{ $wordd . ' ****' } =
                      $::lglobal{seenwords}->{$wordd};
                    $wordwo++;
                }
            }
            $accent{$word}++;
        }
    }
    $::lglobal{wfsaveheader} = "$wordw accented words, $wordwo suspects (marked with ****).";
    sortanddisplaywords( \%display );
    @::wfsearchopt = qw/1 x x 0/;
    $top->Unbusy;
}

#
# Check for Uppercase character following comma
sub commark {
    my $top = $::top;
    ::operationadd('Check , Upper');
    $top->Busy( -recurse => 1 );
    my %display = ();
    my $wordw   = 0;
    my $ssindex = '1.0';
    my $length;
    return if ( nofileloaded($top) );
    $::lglobal{wf_ignore_case} = 0;
    $::lglobal{wclistbox}->delete( '0', 'end' );
    $::lglobal{wclistbox}->insert( 'end', 'Please wait, building list....' );
    $::lglobal{wclistbox}->update;
    my $wholefile = $::textwindow->get( '1.0', 'end' );

    if ($::intelligentWF) {

        # Skip if pattern is: . Hello, John
        $wholefile =~
          s/([\.\?\!]['"]*[\n\s]['"]*\p{Upper}[\p{Alnum}\p{Mark}]*),([\n\s]['"]*\p{Upper})/$1 $2/g;

        # Skip if pattern is: \n\nHello, John
        $wholefile =~ s/(\n\n *['"]*\p{Upper}[\p{Alnum}\p{Mark}]*),( ['"]*\p{Upper})/$1 $2/g;
    }
    while ( $wholefile =~ m/,(['"]*\n*\s*['"]*\p{Upper}[\p{Alnum}\p{Mark}]*)([\.\?\!]?)/g ) {
        my $word = $1;
        next
          if $::intelligentWF
          && $2
          && $2 ne '';    # ignore if word followed by period, !, or ?
        $wordw++;
        $word =~ s/\n/\\n/g;
        $display{ ',' . $word }++;
    }
    $::lglobal{wfsaveheader} =
      "$wordw words with uppercase following commas. " . '(\n means newline)';
    sortanddisplaywords( \%display );
    @::wfsearchopt = qw/0 x x 1/;
    $top->Unbusy;
}

#
# Show words with italic, bold or smallcap markup
sub itwords {
    my $top = $::top;
    ::operationadd('WF Check Ital/Bold/SC');
    $top->Busy( -recurse => 1 );
    $::lglobal{wclistbox}->delete( '0', 'end' );
    my %display  = ();
    my $wordw    = 0;
    my $suspects = '0';
    my %words;
    my $ssindex = '1.0';
    my $length;
    return if ( nofileloaded($top) );
    $::lglobal{wclistbox}->insert( 'end', 'Please wait, building list....' );
    $::lglobal{wclistbox}->update;
    my $wholefile = $::textwindow->get( '1.0', 'end' );
    $::markupthreshold = 0 unless $::markupthreshold;

    my $markuptypes = "i|I|b|B|sc|cite|em|strong|f|g|u";
    while ( $wholefile =~ m/(<($markuptypes)>)(.*?)(<\/($markuptypes)>)/sg ) {
        my $word   = $1 . $3 . $4;
        my $wordwo = $3;
        my $num    = 0;
        $num++ while ( $word =~ /(\S\s)/g );
        next if ( $num >= $::markupthreshold and $::markupthreshold > 0 );    # threshold 0 = unlimited
        $word =~ s/\n/\\n/g;
        $display{$word}++;
        $wordwo =~ s/\n/\\n/g;
        $words{$wordwo} = $display{$word};
    }
    $wordw = scalar keys %display;
    for my $wordwo ( keys %words ) {
        my $wordwo2 = $wordwo;
        $wordwo2 =~ s/\\n/\n/g;
        while ( $wholefile =~ m/(?<=\W)\Q$wordwo2\E(?=\W)/sg ) {
            $display{$wordwo}++;
        }
        $display{$wordwo} = $display{$wordwo} - $words{$wordwo}
          if ( ( $words{$wordwo} ) || ( $display{$wordwo} =~ /\\n/ ) );
        delete $display{$wordwo} unless $display{$wordwo};
    }
    $suspects = ( scalar keys %display ) - $wordw;
    $::lglobal{wfsaveheader} =
      "$wordw words/phrases with markup, $suspects similar without. (\\n means newline)";
    $wholefile = ();
    sortanddisplaywords( \%display );
    @::wfsearchopt = qw/1 x x 0/;
    $top->Unbusy;
}

#
# Pop dialog to allow user to set a threshold word count for italic/bold/smallcap markup
# This is to allow single word/short phrases to be displayed, without displaying
# full sentences in italic, for example.
sub ital_adjust {
    my $top = $::top;
    return if $::lglobal{markuppop};
    $::lglobal{markuppop} = $top->Toplevel( -title => 'Word count threshold', );
    ::initialize_popup_with_deletebinding('markuppop');
    my $f0 = $::lglobal{markuppop}->Frame->pack( -side => 'top', -anchor => 'n' );
    $f0->Label( -text => "Threshold word count for marked up phrase.\n"
          . "Phrases with more words will be skipped.\n"
          . "Threshold of 0 means no limit" )->pack;
    my $f1 = $::lglobal{markuppop}->Frame->pack( -side => 'top', -anchor => 'n' );
    $f1->Entry(
        -width        => 10,
        -textvariable => \$::markupthreshold,
        -validate     => 'key',
        -vcmd         => sub {
            return 1 unless $_[1];
            return 1 unless ( $_[1] =~ /\D/ );
            return 0;
        },
    )->grid( -row => 1, -column => 1, -padx => 2, -pady => 4 );
    $::lglobal{markuppopok} = $f1->Button(
        -command => sub {
            $::markupthreshold = 0 unless $::markupthreshold;    # User has cleared entry field
            ::savesettings();
            ::killpopup('markuppop');
            undef $::lglobal{markuppopok};
        },
        -text  => 'OK',
        -width => 8
    )->grid( -row => 2, -column => 1, -padx => 2, -pady => 4 );
    $::lglobal{markuppop}->bind( '<Return>' => sub { $::lglobal{markuppopok}->invoke; } );
    $::lglobal{markuppop}->bind( '<Escape>' => sub { $::lglobal{markuppopok}->invoke; } );
    $::lglobal{markuppop}->resizable( 'no', 'no' );
}

#
# Display words with hyphens, and allow check for same word without hyphen, with a space,
# or with a double hyphen
sub hyphencheck {
    my $top = $::top;
    ::operationadd('Check hyphens');
    $top->Busy( -recurse => 1 );
    $::lglobal{wclistbox}->delete( '0', 'end' );
    $::lglobal{wclistbox}->insert( 'end', 'Please wait, building word list....' );
    $::lglobal{wclistbox}->update;
    my $wordw   = 0;
    my $wordwo  = 0;
    my %display = ();

    foreach my $word ( keys %{ $::lglobal{seenwords} } ) {
        next if ( $::lglobal{seenwords}->{$word} < 1 );

        # For words with hyphens
        if ( $word =~ /-/ ) {
            $wordw++;
            my $wordtemp = $word;

            # display all words with hyphens unless suspects only is chosen
            $display{$word} = $::lglobal{seenwords}->{$word}
              unless $::lglobal{suspects_only};

            # Check if the same word also appears with a double hyphen
            $word =~ s/-/--/g;
            if ( $::lglobal{seenwordsdoublehyphen}->{$word} ) {

                # display with single and with double hyphen
                $display{ $wordtemp . ' ****' } = $::lglobal{seenwords}->{$wordtemp}
                  if $::lglobal{suspects_only};
                my $aword = $word . ' ****';
                $display{ $word . ' ****' } =
                  $::lglobal{seenwordsdoublehyphen}->{$word};
                $wordwo++;
            }

            # Check if the same word also appears with space
            $word =~ s/-/ /g;
            $word =~ s/  / /g;
            if (   $::twowordsinhyphencheck
                && $::lglobal{seenwordpairs}->{$word} ) {
                my $aword = $word . ' ****';
                $display{$aword} = $::lglobal{seenwordpairs}->{$word};
                $display{ $wordtemp . ' ****' } = $::lglobal{seenwords}->{$wordtemp}
                  if $::lglobal{suspects_only};
                $wordwo++;
            }

            # Check if the same word also appears without a space or hyphen
            $word =~ s/ //g;
            if ( $::lglobal{seenwords}->{$word} ) {
                $display{ $wordtemp . ' ****' } = $::lglobal{seenwords}->{$wordtemp}
                  if $::lglobal{suspects_only};
                my $aword = $word . ' ****';
                $display{$aword} = $::lglobal{seenwords}->{$word};
                $wordwo++;
            }
        }
    }
    if ($::twowordsinhyphencheck) {
        foreach my $word ( keys %{ $::lglobal{seenwordpairs} } ) {
            next if ( $::lglobal{seenwordpairs}->{$word} < 1 );    # never true
                                                                   # For each pair of consecutive words
            if ( $word =~ / / ) {                                  #always true
                my $wordtemp = $word;

                # Check if the same word also appears without a space
                $word =~ s/ //g;
                if ( $::lglobal{seenwords}->{$word} ) {
                    $display{ $word . ' ****' } =
                      $::lglobal{seenwords}->{$word};
                    my $aword = $wordtemp . ' ****';
                    $display{$aword} = $::lglobal{seenwordpairs}->{$wordtemp}
                      unless $display{$aword};
                    $wordwo++;
                }
                $word =~ s/-//g;
                if ( $::lglobal{seenwords}->{$word} ) {
                    $display{ $word . ' ****' } =
                      $::lglobal{seenwords}->{$word};
                    my $aword = $wordtemp . ' ****';
                    $display{$aword} = $::lglobal{seenwordpairs}->{$wordtemp}
                      unless $display{$aword};
                    $wordwo++;
                }
            }
        }
    }
    $::lglobal{wfsaveheader} = "$wordw words with hyphens, $wordwo suspects (marked ****).";
    sortanddisplaywords( \%display );
    @::wfsearchopt = qw/1 x x 0/;
    $top->Unbusy;
}

#
# Find word frequency words that Spell Query does not recognise
sub wordfrequencygetmisspelled {
    $::lglobal{spellsort} = ();
    my $wordw = 0;
    for my $word ( keys %{ $::lglobal{seenwords} } ) {
        if ( not ::spellquerywfwordok($word) ) {
            $::lglobal{spellsort}->{$word} = $::lglobal{seenwords}->{$word} || '0';
            $wordw++;
        }
    }
    return $wordw;
}

#
# Display words not recognised by Spell Query
sub wordfrequencyspellcheck {
    my $top = $::top;
    ::operationadd('Check spelling wordfrequency');
    $top->Busy( -recurse => 1 );
    $::lglobal{wclistbox}->delete( '0', 'end' );
    $::lglobal{wclistbox}->insert( 'end', 'Please wait, building word list....' );
    $::lglobal{wclistbox}->update;
    if ( ::spellqueryinitialize() ) {
        my $wordw = wordfrequencygetmisspelled();
        $::lglobal{wfsaveheader} = "$wordw words not recognised by Spell Query.";
        sortanddisplaywords( \%{ $::lglobal{spellsort} } );
    } else {
        $::lglobal{wclistbox}->insert( 'end', 'Unable to check spelling.' );
    }
    $top->Unbusy;
}

#
# Check character counts
sub charsortcheck {
    my $textwindow = $::textwindow;
    my $top        = $::top;
    ::operationadd('Check Character Cnts');
    $top->Busy( -recurse => 1 );
    $::lglobal{wclistbox}->delete( '0', 'end' );
    return if ( nofileloaded($top) );
    $::lglobal{wclistbox}->insert( 'end', 'Please wait, building list....' );
    $::lglobal{wclistbox}->update;

    my $wholefile = $::textwindow->get( '1.0', 'end' );
    $wholefile = lc($wholefile) if $::lglobal{wf_ignore_case};
    my @words = split( //, $wholefile );    # Split into individual characters

    my $wordw = 0;
    my %chars;
    foreach (@words) {
        $chars{$_}++;
        $wordw++;
    }

    # Replace some (whitespace) characters with a visible display name in the list
    my %display = (
        "\n"   => '*newline*',
        " "    => '*space*',
        "\xA0" => '*nbsp*',
        "\t"   => '*tab*',
    );
    for my $dk ( keys %display ) {
        if ( $chars{$dk} ) {
            $chars{ $display{$dk} } = $chars{$dk};
            delete $chars{$dk};
        }
    }

    $::lglobal{wfsaveheader} = "$wordw characters in the file.";
    sortanddisplaywords( \%chars );
    @::wfsearchopt = qw/0 x x 0/;
    $top->Unbusy;
}

#
# Handle charsuite enabling relating to given character.
# If character is in a selected charsuite, do nothing.
# If in another charsuite, offer to select that suite
# If in none, pop error dialog
sub charsortsuitecontrol {
    my $top  = $::top;
    my $char = shift;             # Line from WF dialog containing character to be checked
    $char =~ s/\d+\s+(\S)/$1/;    # Extract the character to be checked
    return if ::charsuitecheck($char);
    my $suite = ::charsuitefind($char);
    if ($suite) {
        my $reply = $top->messageBox(
            -icon    => 'question',
            -title   => 'Enable Character Suite',
            -type    => 'YesNo',
            -default => 'yes',
            -message =>
              "Character is in the $suite character suite.\nWould you like to enable that suite?",
        );
        if ( $reply =~ /yes/i ) {
            ::charsuiteenable($suite);
            sortanddisplayhighlight();    # Update highlighting
        }
    } else {
        $top->messageBox(
            -icon    => 'warning',
            -title   => 'No Character Suite',
            -type    => 'OK',
            -default => 'ok',
            -message => "No character suite found containing that character.",
        );
    }
}

#
# Run stealth scanno check from within Word Frequency
sub stealthcheck {
    my $top        = $::top;
    my $textwindow = $::textwindow;
    ::operationadd('Check Stealthos Word Frequency');
    ::loadscannos();
    $top->Busy( -recurse => 1 );
    $::lglobal{wclistbox}->delete( '0', 'end' );
    $::lglobal{wclistbox}->insert( 'end', 'Please wait, building list....' );
    $::lglobal{wclistbox}->update;
    my %display = ();
    my ( $line, $word, %list, @words, $scanno );
    my $index = '1.0';
    my $end   = $textwindow->index('end');
    my $wordw = 0;

    while ( ( $scanno, $word ) = each(%::scannoslist) ) {
        $list{$word}   = '';
        $list{$scanno} = '';
    }
    foreach my $word ( keys %{ $::lglobal{seenwords} } ) {
        next unless exists( $list{$word} );
        $wordw++;
        $display{$word} = $::lglobal{seenwords}->{$word};
    }
    $::lglobal{wfsaveheader} = "$wordw suspect words found in file.";
    sortanddisplaywords( \%display );
    @::wfsearchopt = qw/1 x x 0/;
    $top->Unbusy;
}

#
# Check for ae and oe ligatures, including flagging suspects
sub ligaturecheck {
    my $top = $::top;
    ::operationadd('Check words with possible ligatures');
    $top->Busy( -recurse => 1 );
    $::lglobal{wclistbox}->delete( '0', 'end' );
    $::lglobal{wclistbox}->insert( 'end', 'Please wait, building word list....' );
    $::lglobal{wclistbox}->update;
    my %display = ();
    my $wordw   = 0;
    my $wordwo  = 0;

    foreach my $word ( keys %{ $::lglobal{seenwords} } ) {
        next unless ( $word =~ /(ae|AE|Ae|oe|OE|Oe|\xe6|\xc6|\x{0153}|\x{0152})/ );
        $wordw++;

        # Start from non-ligatured versions because Ae/AE and Oe/OE each map to uppercase ligature
        # so it's easier to convert both of those to the ligature than the other way round
        if ( $word !~ /(\xe6|\xc6|\x{0153}|\x{0152})/ ) {
            my $ligword = $word;
            $ligword =~ s/ae/\xe6/g;
            $ligword =~ s/(AE|Ae)/\xc6/g;
            $ligword =~ s/oe/\x{0153}/g;
            $ligword =~ s/(OE|Oe)/\x{0152}/g;

            # If ligature version also seen, display both
            if ( $::lglobal{seenwords}->{$ligword} ) {
                $display{$ligword} = $::lglobal{seenwords}->{$ligword}
                  if $::lglobal{suspects_only};    # Lig word added below if not suspects only
                $wordwo++;
                $display{"$word ****"} = $::lglobal{seenwords}->{$word};
            } elsif ( not $::lglobal{suspects_only} ) {    # Only non-lig seen, no need to display if suspects only
                $display{$word} = $::lglobal{seenwords}->{$word};
            }
        } elsif ( not $::lglobal{suspects_only} ) {    # Lig word added above if suspects only
            $display{$word} = $::lglobal{seenwords}->{$word};
        }
    }
    $::lglobal{wfsaveheader} = "$wordw words with ligatures, $wordwo suspects (marked with ****).";
    sortanddisplaywords( \%display );
    @::wfsearchopt = qw/1 x x 0/;
    $top->Unbusy;
}

#
# Pop the Harmonics dialog - to check for similar (mis)spellings of words
sub harmonicspop {
    my $top = $::top;
    my ( $line, $word, $sword, $snum, @savesets, $wc );
    if ( $::lglobal{hpopup} ) {
        $::lglobal{hpopup}->deiconify;
        $::lglobal{hpopup}->raise;
        $::lglobal{hlistbox}->delete( '0', 'end' );
    } else {
        $::lglobal{hpopup} = $top->Toplevel;
        $::lglobal{hpopup}->title('Word harmonics');
        ::initialize_popup_with_deletebinding('hpopup');
        my $frame = $::lglobal{hpopup}->Frame->pack( -fill => 'both', -expand => 'both', );
        $::lglobal{hlistbox} = $frame->Scrolled(
            'Listbox',
            -scrollbars  => 'se',
            -background  => $::bkgcolor,
            -font        => 'proofing',
            -selectmode  => 'single',
            -activestyle => 'none',
        )->pack(
            -anchor => 'nw',
            -fill   => 'both',
            -expand => 'both',
            -padx   => 2,
            -pady   => 2
        );
        ::drag( $::lglobal{hlistbox} );
        $::lglobal{hpopup}->protocol(
            'WM_DELETE_WINDOW' => sub {
                ::killpopup('hpopup');
                undef $::lglobal{hlistbox};
            }
        );
        $::lglobal{hlistbox}->eventAdd( '<<search>>' => '<ButtonRelease-3>' );
        $::lglobal{hlistbox}->bind(
            '<<search>>',
            sub {
                $::lglobal{hlistbox}->selectionClear( 0, 'end' );
                $::lglobal{hlistbox}->selectionSet(
                    $::lglobal{hlistbox}->index(
                            '@'
                          . ( $::lglobal{hlistbox}->pointerx - $::lglobal{hlistbox}->rootx )
                          . ','
                          . ( $::lglobal{hlistbox}->pointery - $::lglobal{hlistbox}->rooty )
                    )
                );
                my ($sword) = $::lglobal{hlistbox}->get( $::lglobal{hlistbox}->curselection );
                ::searchpopup();
                $sword =~ s/\d+\s+([\w'-]*)/$1/;
                $sword =~ s/\s+\*\*\*\*$//;
                $::lglobal{searchentry}->delete( 0, 'end' );
                $::lglobal{searchentry}->insert( 'end', $sword );
                ::updatesearchlabels();
                $::lglobal{searchentry}->after( $::lglobal{delay} );
            }
        );
        $::lglobal{hlistbox}->eventAdd( '<<find>>' => '<Double-Button-1>' );
        $::lglobal{hlistbox}->bind(
            '<<find>>',
            sub {
                return unless $::lglobal{hlistbox}->index('active');
                $top->Busy( -recurse => 1 );
                $sword = $::lglobal{hlistbox}->get('active');
                return unless ( $::lglobal{hlistbox}->curselection );
                $sword =~ s/(\d+)\s+([\w'-]*)/$2/;
                $snum = $1;
                $sword =~ s/\s+\*\*\*\*$//;
                @savesets = @::sopt;

                unless ($snum) {
                    ::searchoptset(qw/0 x x 1/);
                    $sword = "(?<=-)$sword|$sword(?=-)";
                }
                ::searchfromstartifnew($sword);
                ::searchtext($sword);
                ::searchoptset(@savesets);
                $top->Unbusy( -recurse => 1 );
            }
        );
        $::lglobal{hlistbox}->bind(
            '<Down>',
            sub {
                return unless defined $::lglobal{wclistbox};
                my $index = $::lglobal{wclistbox}->index('active');
                $::lglobal{wclistbox}->selectionClear( '0', 'end' );
                $::lglobal{wclistbox}->activate( $index + 1 );
                $::lglobal{wclistbox}->selectionSet( $index + 1 );
                $::lglobal{wclistbox}->see('active');
                harmonics( $::lglobal{wclistbox}->get('active') );
                harmonicspop();
                $::lglobal{hpopup}->break;
            }
        );
        $::lglobal{hlistbox}->bind(
            '<Up>',
            sub {
                return unless defined $::lglobal{wclistbox};
                my $index = $::lglobal{wclistbox}->index('active');
                $::lglobal{wclistbox}->selectionClear( '0', 'end' );
                $::lglobal{wclistbox}->activate( $index - 1 );
                $::lglobal{wclistbox}->selectionSet( $index - 1 );
                $::lglobal{wclistbox}->see('active');
                harmonics( $::lglobal{wclistbox}->get('active') );
                harmonicspop();
                $::lglobal{hpopup}->break;
            }
        );
        $::lglobal{hlistbox}->eventAdd( '<<harm>>' => '<Control-Button-1>' );
        $::lglobal{hlistbox}->bind(
            '<<harm>>',
            sub {
                return unless ( $::lglobal{hlistbox}->curselection );
                harmonics( $::lglobal{hlistbox}->get('active') );
                harmonicspop();
            }
        );
    }
    my $active = $::lglobal{wclistbox}->get('active');
    $active =~ s/\d+\s+([\w'-]*)/$1/;
    $active =~ s/\*\*\*\*$//;
    $active =~ s/\s//g;
    $::lglobal{hlistbox}->insert( 'end', 'Please wait... searching...' );
    $::lglobal{hlistbox}->update;
    if ( defined $::lglobal{harmonics} && $::lglobal{harmonics} == 2 ) {
        harmonics2($active);
        $wc = scalar( keys( %{ $::lglobal{harmonic} } ) );
        $::lglobal{hlistbox}->delete( '0', 'end' );
        $::lglobal{hlistbox}->insert( 'end', "$wc 2nd order harmonics for $active." );
    } else {
        harmonics($active);
        $wc = scalar( keys( %{ $::lglobal{harmonic} } ) );
        $::lglobal{hlistbox}->delete( '0', 'end' );
        $::lglobal{hlistbox}->insert( 'end', "$wc 1st order harmonics for $active." );
    }
    foreach my $word ( ::natural_sort_alpha( keys %{ $::lglobal{harmonic} } ) ) {
        $line = sprintf( "%-8d %s", $::lglobal{seenwords}->{$word}, $word );    # Print to the file
        $::lglobal{hlistbox}->insert( 'end', $line );
    }
    %{ $::lglobal{harmonic} } = ();
    $::lglobal{hlistbox}->focus;
}

#
# Find words (mis)spelled similarly to given word
sub harmonics {
    my $word = shift;
    $word =~ s/\d+\s+([\w'-]*)/$1/;
    $word =~ s/\*\*\*\*$//;
    $word =~ s/\s//g;
    my $length = length $word;
    for my $test ( keys %{ $::lglobal{seenwords} } ) {
        next                            if ( abs( $length - length $test ) > 1 );
        $::lglobal{harmonic}{$test} = 1 if ( distance( $word, $test ) <= 1 );
    }
}

#
# Find words (mis)spelled similarly to given word allowing distance of 2
sub harmonics2 {
    my $word = shift;
    $word =~ s/\d+\s+([\w'-]*)/$1/;
    $word =~ s/\*\*\*\*$//;
    $word =~ s/\s//g;
    my $length = length $word;
    for my $test ( keys %{ $::lglobal{seenwords} } ) {
        next                            if ( abs( $length - length $test ) > 2 );
        $::lglobal{harmonic}{$test} = 1 if ( distance( $word, $test ) <= 2 );
    }
}

#
# Levenshtein edit distance calculation
sub distance {
    return Text::LevenshteinXS::distance(@_);
}

#
# Sort and display list of words in the WF dialog
sub sortanddisplaywords {
    my $href = shift;
    $::lglobal{wclistbox}->delete( '0', 'end' );
    $::lglobal{wclistbox}->insert( 'end', 'Please wait, sorting list....' );
    $::lglobal{wclistbox}->update;
    my $lastletter = '0';
    if ( $::alpha_sort eq 'f' ) {    # Sorted by word frequency
        for ( ::natural_sort_freq($href) ) {
            my $line = sprintf( "%-8d %s", $$href{$_}, $_ );    # Print to the file
            $::lglobal{wclistbox}->insert( 'end', $line );
        }
    } elsif ( $::alpha_sort eq 'a' ) {    # Sorted alphabetically
        for ( ::natural_sort_alpha( keys %$href ) ) {
            my $line = sprintf( "%-8d %s", $$href{$_}, $_ );    # Print to the file
            $::lglobal{wclistbox}->insert( 'end', $line );

            # Get the first letter of the deaccented form of the word's first letter
            my $firstletter = substr( lc( ::deaccentsort( substr( $_, 0, 1 ) ) ), 0, 1 );
            if ( $firstletter ne $lastletter && $firstletter =~ /[a-z]/ ) {
                $lastletter = $firstletter;
                my $thispos = $::lglobal{wclistbox}->size;
                $::lglobal{wfpop}->Tk::bind(
                    '<Key-' . $firstletter . '>' => eval {
                        sub { \$::lglobal{wclistbox}->yview( $thispos - 2 ) }
                    }
                );
            }
        }
    } elsif ( $::alpha_sort eq 'l' ) {    # Sorted by word length
        for ( ::natural_sort_length( keys %$href ) ) {
            my $line = sprintf( "%-8d %s", $$href{$_}, $_ );    # Print to the file
            $::lglobal{wclistbox}->insert( 'end', $line );
        }
    }
    $::lglobal{wclistbox}->delete('0');
    $::lglobal{wclistbox}->insert( '0', $::lglobal{wfsaveheader} );
    sortanddisplayhighlight();
    $::lglobal{wclistbox}->update;
}

#
# Handling highlighting in the word frequency dialog list
# Currently only used for Character Count, but safe to call any time
sub sortanddisplayhighlight {
    my $force = shift;    # Force highlighting clear even if highlight flag is off

    return
      unless Tk::Exists( $::lglobal{wclistbox} )                   # Only highlight if dialog is popped
      and $::lglobal{wfsaveheader} =~ /characters in the file/;    # Only highlight if showing Character Count
    return unless $::charsuitewfhighlight or $force;               # Only highlight if flag on, or being forced

    my $numentries = $::lglobal{wclistbox}->size();
    return if $numentries < 1;

    # Get default background color from first (summary) line
    my $defaultcolor = $::lglobal{wclistbox}->itemcget( 0, -background );

    for my $entry ( 1 .. $numentries - 1 ) {
        my $char = $::lglobal{wclistbox}->get($entry);
        $char =~ s/\d+ +(.+)/$1/;
        next if length($char) > 1;    # Only consider highlight for single character entries

        my $color = ::charsuitecheck($char) ? $defaultcolor : 'yellow';
        $color = $defaultcolor if $force and not $::charsuitewfhighlight;    # Override flag if forcing
        $::lglobal{wclistbox}->itemconfigure( $entry, -background => $color );
    }
}

#
# Check file has been loaded (or saved), i.e. has a filename
# before doing WF operations
sub nofileloaded {
    my $top = shift;
    if ( $::lglobal{global_filename} =~ m/No File Loaded/ ) {
        $::lglobal{wclistbox}->insert( 'end', 'Please save the file first.' );
        $::lglobal{wclistbox}->update;
        $top->Unbusy;
        return 1;
    }
}

#
# Add shortcuts to WF word list
sub add_navigation_events {
    my ($dialog_box) = @_;
    $dialog_box->eventAdd(
        '<<pnext>>' => '<Next>',
        '<Prior>', '<Up>', '<Down>'
    );
    $dialog_box->bind(
        '<<pnext>>',
        sub {
            $dialog_box->selectionClear( 0, 'end' );
            $dialog_box->selectionSet( $dialog_box->index('active') );
        }
    );
    $dialog_box->bind(
        '<Home>',
        sub {
            $dialog_box->selectionClear( 0, 'end' );
            $dialog_box->see(0);
            $dialog_box->selectionSet(1);
            $dialog_box->activate(1);
        }
    );
    $dialog_box->bind(
        '<End>',
        sub {
            $dialog_box->selectionClear( 0, 'end' );
            $dialog_box->see( $dialog_box->index('end') );
            $dialog_box->selectionSet( $dialog_box->index('end') - 1 );
            $dialog_box->activate( $dialog_box->index('end') - 1 );
        }
    );
}

1;
