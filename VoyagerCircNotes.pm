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
		return;
	}
}

sub getFieldNames {
	my($self) = shift;
	my($noticeId) = shift;
	
	if (defined($self->{'_sifFields'}{$noticeId})) {
		return @{$self->{'_sifFields'}{$noticeId}};
	} else {
		return;
	}

}

sub getFieldCount {
	my($self) = shift;
	my($noticeId) = shift;

	if (defined($self->{'_sifIndex'}{$noticeId})) {
		return scalar($self->{'_sifIndex'}{$noticeId});
	} else {
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
		push @{$self->{'_data'}}, [split(/[|]/, $_)];
	}
}

sub sortBy {
	my($self) = shift;
	my(@fields) = @_;

	my(@data) = sort { 
		my($aCalc, $bCalc);
		foreach my $f (@fields) {
			$aCalc .= $a->[$self->getFieldPosition($a->[$self->getNoticeIdPosition()], $f)].'~';
			$bCalc .= $b->[$self->getFieldPosition($b->[$self->getNoticeIdPosition()], $f)].'~';
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
		my($row);
		foreach my $f ($self->getFieldNames($noticeId)) {
			$row->{ $f } = $d->[ $self->getFieldPosition($noticeId, $f) ];
		}
		push(@msg, $row);
		($lastNid, $lastPid) = ($noticeId, $patronId);
	}
	if (@msg) {
		my(@newMessage) = @msg;
		@msg = ();
		push @result, \@newMessage;
	}
	return @result;
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
			$output .= $l->{$f};
		}
		# output a newline at the end of the line
		$output .= "\n";
	}
	return $output;
}
1;

use Mojo::Template;
use Sys::Hostname;
use Email::Sender::Simple;
use Email::MIME;
use Email::Address::XS;

my($crcnote) = new VoyagerCircNotes();
$crcnote->readInput();
my($counter) = 0;
foreach my $m ($crcnote->byNoticeAndPatron()) {
	my($template_file) = template_filename($m->[0]->{'NoticeId'});
	my($failureMessage) = '';
	if (-r $template_file && Email::Address::XS->parse($m->[0]->{'Email'})->is_valid()) {
		my($message) = { %{$m->[0]}, '_itemList' => $m };
		my($t) = Mojo::Template->new();
		$t->vars(1);
		my($render) = $t->render_file($template_file, $message);
		# check if the result is email text, or an error object
		if (!ref($render)) {
			# send the email
			# find the headers and body within the plaintext template
			my(@headers, $body, @lines);
			# get all groupings of lines
			@lines = split(/\n\n/m, $render);
			# the first grouping is the headers
			@headers = split(/\n/m, $lines[0]);
			shift(@lines);
			# the remaining groupings go back together as the body
			$body = join("\n\n", @lines);
			# we'll need to parse the headers
			my($mailHeader);
			foreach my $h (@headers) {
				# Split the name of the header from the value of the header
				my(@parts, $headerName, $headerValue);
				@parts = split(':', $h);
				# Trim the leading and trailing whitespace from the name and value
				$headerName = trim(shift(@parts));
				$headerValue = trim(join(':', @parts));
				# Don't actually send mail if not production
				if (hostname() !~ m/prod/i && $headerName =~ m/^(to|cc|bcc)$/i) {
					my(@oldAddresses) = Email::Address::XS->parse($headerValue);
					my(@newAddresses);
					# replace the domain with mailinator.com or similar
					foreach my $a (@oldAddresses) {
						my($new) = $a->address();
						$new =~ s/@/./;
						$new .= '@mailinator.com';
						$a->address( $new );
						push(@newAddresses, $a);
					}
					$headerValue = join(',', @newAddresses);
				}
				push(@$mailHeader, ($headerName => $headerValue));
			}
			# add one or more parts
			my(@parts);
			# N.b.: UTF-8 is assumed
			my($characterSet) = 'UTF-8';
			# If the first characters is a <, this is probably HTML
			if (substr($body, 0, 1) eq '<') {
				my($htmlBody) = $body;
				push @parts, Email::MIME->create(
					'body_str' => $htmlBody,
					'attributes' => {
						'content_type' => 'text/html',
						'encoding' => 'quoted-printable',
						'charset' => $characterSet,
					},
				);
				eval 'use HTML::WikiConverter::Markdown';
				if ($@) {
					use HTML::FormatText;
					$body = HTML::FormatText->format_string($body);
				} else {
					use HTML::WikiConverter;
					my($converter) = new HTML::WikiConverter('dialect' => 'Markdown');
					$body = $converter->html2wiki($body);
				}
			}
			# add the plaintext body
			push @parts, Email::MIME->create(
				'body_str' => $body,
				'attributes' => {
					'content_type' => 'text/plain',
					'encoding' => 'quoted-printable',
					'charset' => $characterSet,
				}
			);
			# place the parts in a message
			my($email) = Email::MIME->create(
				'header_str' => $mailHeader,
				'parts' => \@parts,
			);
			#my($result) = Email::Sender::Simple->try_to_send($email);
			my($result) = 0;
			print $email->as_string();
			if ($result->isa('Email::Sender::Failure')) {
				# an error occurred
				$failureMessage = $result->code.' '.$result->message;
			}
		} else {
			# an error occured
			$failureMessage = $render->to_string();
		}
		# Handle a failure condition
		if ($failureMessage) {
			warn $failureMessage;
			print $crcnote->getLinesFromMessage($m);
		}
	} else {
		print $crcnote->getLinesFromMessage($m);
	}
}

sub trim {
	my($var) = shift;
	$var =~ s/\s+$//;
	$var =~ s/^\s+//;
	return $var;
}

sub template_filename {
	my($notice) = shift;
	return 'crcnotes/'.$notice.'.tmpl';
}

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

