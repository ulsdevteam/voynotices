#!/m1/shared/bin/perl -w

=head1 NAME

VoyagerCircNotes.pm

This class provides methods to interact with a Voyager 9/10 SIF notices file.

=head1 SUMMARY

Read from STDIN, pre-process notice line(s), write unprocessed notice line(s) to output.

    my($notices) = new VoyagerCircNotes();
    while (<>) {
      warn 'Did not understand: '.$_ unless $notices->readLine($_);
    }
    # Remove Hold/Recall Cancellations, leave other lines unchanged.
    foreach my $message ($notices->byRow()) {
      print $notices->getLinesFromMessage($message) unless ($message->[0]->{'NoticeId'} eq '00');
    }

=head1 COPYRIGHT AND LICENSE

Copyright (c) University of Pittsburgh

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.
=cut

package VoyagerCircNotes;
use strict;

=head2 new()
Create a new instance of the class

    my($notices) = new VoyagerCircNotes();

=cut

sub new {
	my $class = shift;
	my $self = {
		'_sifFields' => undef,
		'_sifFieldIndex' => undef,
		'_data' => undef,
	};
	bless $self, $class;
	$self->_setupSifFields();
	return $self;
}

sub _setupSifFields() {
	my($self) = shift;
	if ($self->{'_sifFields'}) {
		return;
	}

	# hash $sifIndex describes the position of each field by name
	my(%sifIndex);

	# hash $sifFields describes the SIF structure
	my(%sifFields) = (
		# Shared by all SIF rows
		'CORE' => [
			'NoticeId',
			'VersionNumber',
			'Email',
			'PatronId',
			'LastName',
			'FirstName',
			'PatronTitle',
			'Addr1',
			'Addr2',
			'Addr3',
			'Addr4',
			'Addr5',
			'City',
			'State',
			'PostalCode',
			'Country',
			'Phone',
			'CurrentDate',
			'InstitutionName',
			'Library',
			'LibAddr1',
			'LibAddr2',
			'LibAddr3',
			'LibCity',
			'LibState',
			'LibPostalCode',
			'LibCountry',
			'LibPhone',
			'ItemTitle',
			'ItemAuthor',
			'ItemId',
			'ItemCall',
			'Enum'
		],
		# Hold/Recall Cancellation
		'00' => [
		],
		# Item Available
		'01' => [
			'ExpirationDate'
		],
		# Overdue
		'02' => [
			'DueDate',
			'Sequence',
			'ProxyLastName',
			'ProxyFirstName',
			'ProxyTitle',
			'CopyNumber'
		],
		# Recall
		'03' => [
			'DueDate',
			'ProxyLastName',
			'ProxyFirstName',
			'ProxyTitle'
		],
		# Recall Overdue
		'04' => [
			'DueDate',
			'Sequence',
			'ProxyLastName',
			'ProxyFirstName',
			'ProxyTitle'
		],
		# Fine Fee
		'05' => [
			'FineFeeDate',
			'FineFeeDescription',
			'FineFeeAmount',
			'FineFeeBalance',
			'PreviouslyBilled',
			'TotalFinesFees',
			'DueDateWhenFined',
			'DueDate'
		],
		# Courtesy
		'07' => [
			'DueDate',
			'ProxyLastName',
			'ProxyFirstName',
			'ProxyTitle'
		]
	);
	
	# prepend the core fields to each notice type
	foreach my $noticeId (keys(%sifFields)) {
		if ($noticeId ne 'CORE') {
			$sifFields{$noticeId} = [@{$sifFields{'CORE'}}, @{$sifFields{$noticeId}}];
			my($i) = 0;
			foreach my $field (@{$sifFields{$noticeId}}) {
				$sifIndex{$noticeId}{$field} = $i++;
			}
		}
	}
	delete($sifFields{'CORE'});

	$self->{'_sifFields'} = {%sifFields};
	$self->{'_sifIndex'} = {%sifIndex};
	return;
}

=head2 getFieldPosition( $noticeId, $fieldName )
Get the 0-based position of a field by name for a notice type.

    my($notices) = new VoyagerCircNotes();
    my($position) = $notices->getFieldPosition('01', 'InstitutionName');

=cut

sub getFieldPosition {
	my($self) = shift;
	my($noticeId) = shift;
	my($fieldName) = shift;

	if (defined($self->{'_sifIndex'}{$noticeId})) {
		return $self->{'_sifIndex'}{$noticeId}{$fieldName};
	} else {
		warn 'Notice type "'.$noticeId.'" is invalid';
		return;
	}
}

=head2 getFieldNames( $noticeId )
Get an array of all fields by name for a notice type. Returns false with warning if notice type is unknown.

    my($notices) = new VoyagerCircNotes();
    my(@fields) = $notices->getFieldNames('01');

=cut

sub getFieldNames {
	my($self) = shift;
	my($noticeId) = shift;
	
	if (defined($self->{'_sifFields'}{$noticeId})) {
		return @{$self->{'_sifFields'}{$noticeId}};
	} else {
		warn 'Notice type "'.$noticeId.'" is invalid';
		return;
	}

}

=head2 getFieldCount( $noticeId )
Get a count of the expected fields for a notice type.  Returns false with warning if notice type is unknown.

    my($notices) = new VoyagerCircNotes();
    my($count) = $notices->getFieldCount('01');

=cut

sub getFieldCount {
	my($self) = shift;
	my($noticeId) = shift;

	if (defined($self->{'_sifIndex'}{$noticeId})) {
		return scalar(keys(%{$self->{'_sifIndex'}{$noticeId}}));
	} else {
		warn 'Notice type "'.$noticeId.'" is invalid';
		return;
	}
}

=head2 getNoticeIdPostion()
Returns the 0-based offset of a field representing the notice type.

    my($notices) = new VoyagerCircNotes();
    my($noticeTypeOffset) = $notices->getNoticeIdPosition();

=cut

sub getNoticeIdPosition {
	my($self) = shift;
	return 0;
}

=head2 readInput()
Slurp input contents into memory (using C<< <> >>).  Returns true if all lines successful, false otherwise.

    my($notices) = new VoyagerCircNotes();
    if ($notices->readInput()) {
      print 'All lines from <> read successfully';
    }

=cut

sub readInput {
	my($self) = shift;

	# read from STDIN
	my($success) = 1;
	while ($_ = <>) {
		$success = $success & $self->readLine($_);
	}
	return $success;
}

=head2 readLine()
Add a line of input to memory.  Returns true or false regarding success.

    my($notices) = new VoyagerCircNotes();
    while (<>) {
      warn 'Did not understand: '.$_ unless $notices->readLine($_);
    }

=cut

sub readLine {
	my($self) = shift;
	my($line) = shift;

	chomp $line;
	# split without limit (-1) to get trailing empty fields
	my(@fields) = split(/[|]/, $line, -1);
	if (defined($self->{'_sifFields'}{@fields[$self->getNoticeIdPosition()]})) {
		push @{$self->{'_data'}}, \@fields;
		return 1;
	} else {
		return 0;
	}
}

=head2 sortBy( @fields )
Sort in-memory contents by a set of C<@fields>.

    my($notices) = new VoyagerCircNotes();
    $notices->readInput();
    $notices->sortBy( 'NoticeId', 'PatronId' );

=cut

sub sortBy {
	my($self) = shift;
	my(@fields) = @_;

	my(@data) = sort { 
		my($aCalc, $bCalc) = ('', '');
		foreach my $f (@fields) {
			if (defined($self->getFieldPosition($a->[$self->getNoticeIdPosition()], $f)) && defined($self->getFieldPosition($b->[$self->getNoticeIdPosition()], $f))) {
				$aCalc .= $a->[$self->getFieldPosition($a->[$self->getNoticeIdPosition()], $f)].'~';
				$bCalc .= $b->[$self->getFieldPosition($b->[$self->getNoticeIdPosition()], $f)].'~';
			}
		}
		$aCalc cmp $bCalc;
	} @{$self->{'_data'}};
	return @data;
}

=head2 byNoticeAndPatron( )
Sort in-memory contents by NoticeId and PatronId, and return a set of messages (arrayrefs) with items grouped under a Notice Type and Patron.

    my($notices) = new VoyagerCircNotes();
    $notices->readInput();
    foreach my $message ($notices->byNoticeAndPatron()) {
      print 'Patron '.$message->[0]->{'LastName'}.' has '.scalar(@$message).' notices of type '.$message->[0]->{'NoticeId'}."\n";
    }

=cut

sub byNoticeAndPatron {
	my($self) = shift;

	my(@data, @result);

	# sort by NoticeId and PatronId
	@data = $self->sortBy('NoticeId', 'PatronId');

	# process each data row into a grouping
	my($lastNtype, $lastNid, $lastPid, @msg, $d);
	while ($d = shift(@data)) {
		my($noticeId) = $d->[$self->getNoticeIdPosition()];
		my($patronId) = $d->[$self->getFieldPosition($noticeId, 'PatronId')];
		# check for a change in the notice and/or patron
		if ($lastNid && $lastPid) {
			if ($lastNid ne $noticeId || $lastPid ne $patronId) {
				# check for a queued message
				if (@msg) {
					my(@newMessage) = @msg;
					@msg = ();
					push @result, \@newMessage;
				}
			}
		}
		push(@msg, $self->_dataToHashRef($d));
		($lastNid, $lastPid) = ($noticeId, $patronId);
	}
	if (@msg) {
		my(@newMessage) = @msg;
		@msg = ();
		push @result, \@newMessage;
	}
	return @result;
}

=head2 byNoticeAndPatronAndItem( )
Sort in-memory contents by NoticeId and PatronId and ItemId, and return a set of messages (arrayrefs) with instances grouped under under a Notice Type and Patron and Item.

    my($notices) = new VoyagerCircNotes();
    $notices->readInput();
    foreach my $message ($notices->byNoticeAndPatronAndItem()) {
      print 'Patron '.$message->[0]->{'LastName'}.' has '.scalar(@$message).' notices of type '.$message->[0]->{'NoticeId'}.' for Item '.$message->[0]->{'ItemId'}."\n";
    }

=cut

sub byNoticeAndPatronAndItem {
	my($self) = shift;

	my(@data, @result);

	# sort by NoticeId and PatronId
	@data = $self->sortBy('NoticeId', 'PatronId', 'ItemId');
	my($d);
	while ($d = shift(@data)) {
		push(@result, [$self->_dataToHashRef($d)]);
	}
	return @result;
}

=head2 byRow( )
List every row from memory as a solitary arrayref.

    my($notices) = new VoyagerCircNotes();
    $notices->readInput();
    foreach my $message ($notices->byRow()) {
      print 'Patron '.$message->[0]->{'LastName'}.' has a notice of type '.$message->[0]->{'NoticeId'}.' for Item '.$message->[0]->{'ItemId'}."\n";
    }

=cut

sub byRow {
	my($self) = shift;
	my(@data, @result);
	@data = @{$self->{'_data'}};
	my($d);
	while ($d = shift(@data)) {
		push(@result, [$self->_dataToHashRef($d)]);
	}
	return @result;
}

sub _dataToHashRef {
	my($self) = shift;
	my($d) = shift;
	my($noticeId) = $d->[$self->getNoticeIdPosition()];
	my($row);
	foreach my $f ($self->getFieldNames($noticeId)) {
		$row->{ $f } = $d->[ $self->getFieldPosition($noticeId, $f) ];
	}
	return $row;
}

=head2 getLinesFromMessage( $message )
Give a message (array of arrayrefs), reconsitute the SIF input line(s) represented.

    my($notices) = new VoyagerCircNotes();
    $notices->readInput();
    foreach my $message ($notices->byRow()) {
      print $notices->getLinesFromMessage($message);
    }

=cut

sub getLinesFromMessage() {
	my($self) = shift;
	my($msg) = shift;
	# reconstruct original lines for output
	# for each line
	my($output) = '';
	foreach my $l (@$msg) {
		# for each field in the SIF
		my($pipe) = 0;
		foreach my $f ($self->getFieldNames($l->{'NoticeId'})) {
			# output a pipe if not the first field
			if ($pipe) {
				$output .= '|';
			} else {
				$pipe = 1;
			}
			# output the field
			if (defined($l->{$f})) {
				$output .= $l->{$f};
			} else {
				warn 'Field '.$f.' not defined for type '.$l->{'NoticeId'};
			}
		}
		# output a newline at the end of the line
		$output .= "\n";
	}
	return $output;
}
1;
__END__

