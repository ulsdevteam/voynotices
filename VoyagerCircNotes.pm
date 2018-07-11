#!/m1/shared/bin/perl -w
use strict;

package VoyagerCircNotes;

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
			'ProxyTitle'
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

sub getNoticeIdPosition {
	my($self) = shift;
	return 0;
}

sub readInput {
	my($self) = shift;

	# read from STDIN
	while ($_ = <>) {
		chomp $_;
		# split without limit (-1) to get trailing empty fields
		push @{$self->{'_data'}}, [split(/[|]/, $_, -1)];
	}
}

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

=head1 NAME

VoyagerCircNotes.pm

This script will send emails for circulation notices

=head1 USAGE

Read from STDIN, pre-process notice line(s), write notice line(s) to output (if pre-processing did not fully handle the line).

=begin code

for n in $RPT_DIR/crcnotes.*.inp; do mv $n $n.preprocess; perl VoyagerCircNotes.pm < $n.preprocess > $n; done

=end code

=head1 COPYRIGHT AND LICENSE

Copyright (c) University of Pittsburgh

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

