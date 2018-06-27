#!/m1/shared/bin/perl -w
use strict;

# Copyright (c) University of Pittsburgh
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# This script will read in a crcnotices SIF (pipe delimited) from STDIN and pre-process it to STDOUT.
# If lines within the SIF can be sent via email, these messages will be sent and the lines omitted from the output.
# If lines cannot be sent via email, these lines will be passed through to output, but will be sorted as a side effect.
#
# Strategy:
# Read STDIN
# Sort lines by NoticeId and PatronID to group items for the same patron together in one message
# Compile related lines into a hash which contains:
#  - the key-value pairs for the first line
#  - a _itemList key which contains an array of each line as key-value pairs
# Pass this hash to a template processor, which may pull notice and patron information from the top level key-values,
# and pull item information from the _itemList key-value array.
# If the template can be processed successfully, sent it as an email.
# If the template cannot be processed successfully, restore the _itemList array as STDOUT
# STDOUT may be written to a file for processing by Reporter

use List::Util;
use Mojo::Template;
use Sys::Hostname;
use Email::Sender::Simple;
use Email::MIME;
use Email::Address::XS;

# hash $variables describes the SIF structure
my(%variables) = (
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

# Remember the core positions of NoticeId and PatronId for sorting later
# Remember the core position of Email for checking for address later
my($nid, $pid, $eml);
($nid) = List::Util::first { $variables{'CORE'}->[$_] eq 'NoticeId' } 0 .. scalar(@{$variables{'CORE'}}) - 1;
($pid) = List::Util::first { $variables{'CORE'}->[$_] eq 'PatronId' } 0 .. scalar(@{$variables{'CORE'}}) - 1;
($eml) = List::Util::first { $variables{'CORE'}->[$_] eq 'Email' } 0 .. scalar(@{$variables{'CORE'}}) - 1;

# prepend the core fields to each notice type
foreach my $k (keys(%variables)) {
	if ($k ne 'CORE') {
		$variables{$k} = [@{$variables{'CORE'}}, @{$variables{$k}}];
	}
}
delete($variables{'CORE'});

# We'll use this variable to sort the incoming date, grouping by notice type, patron, and library.
my(@data);
# We'll use this variable to present the messages as a hash
my(%msg);

# read from STDIN
while ($_ = <>) {
	chomp $_;
	push @data, [split(/[|]/, $_)];
}

# sort by NoticeId and PatronId
@data = sort { join('~', ($a->[$nid],$a->[$pid])) cmp join('~', ($b->[$nid],$b->[$pid])) } @data;

# process any eligible notices
my($lastNid, $lastPid);
foreach my $d (@data) {
	# check for a change in the notice and/or patron
	if ($lastNid && $lastPid) {
		if ($lastNid ne $d->[$nid] || $lastPid ne $d->[$pid]) {
			# check for a queued message
			if (%msg) {
				# Initialize the template processor
				my($t) = Mojo::Template->new();
				$t->vars(1);
				my($render) = $t->render_file('crcnotes/'.$d->[$nid].'.tmpl', \%msg);
				my($failureMessage) = '';
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
					# we'll need to parse the headers for Email::Simple
					my($mailHeader);
					foreach my $h (@headers) {
						# Split the name of the header from the value of the header
						my(@parts, $headerName, $headerValue);
						@parts = split(':', $h);
						# Trim the leading and trailing whitespace from the name and value
						$headerName = shift(@parts);
						$headerName =~ s/\s+$//;
						$headerName =~ s/^\s+//;
						$headerValue = join(':', @parts);
						$headerValue =~ s/\s+$//;
						$headerValue =~ s/^\s+//;
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
					my($email) = Email::MIME->create(
						'header_str' => $mailHeader,
						'parts' => [
							$body
							# TODO: handle HTML + plaintext?
						]
					);
					my($result) = Email::Sender::Simple->try_to_send($email);
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
					# reconstruct original lines for output
					# for each line
					foreach my $l (@{$msg{'_itemList'}}) {
						# for each field in the SIF
						my($pipe) = 0;
						foreach my $i (@{$variables{$d->[$nid]}}) {
							# output a pipe if not the first field
							if ($pipe) {
								print '|';
							} else {
								$pipe = 1;
							}
							# output the field
							print $l->{$i};
						}
						# output a newline at the end of the line
						print "\n";
					}
				}
				undef %msg;
			}
		}
	}
	# check if we have an email template to process this known notice type
	if (defined($variables{$d->[$nid]}) && -r 'crcnotes/'.$d->[$nid].'.tmpl' && $d->[$eml]) {
		# do we have a message in progress for the same user and notice?
		if (%msg) {
			# continue prior message
			# find the next item index by counting existing indexes
			my($listNumber) = scalar(@{$msg{'_itemList'}});
			foreach my $i (0 .. scalar(@{$variables{$d->[$nid]}}) - 1) {
				# Add this key to the _itemList
				$msg{ '_itemList' }[$listNumber]{ $variables{$d->[$nid]}->[$i] } = $d->[$i];
			}
		} else {
			# start a new message
			# the first record's keys will exist at the top level
			# and an _itemList key will hold an array of all related records
			$msg{ '_itemList' } = ();
			foreach my $i (0 .. scalar(@{$variables{$d->[$nid]}}) - 1) {
				# Assign the data field $i to $msg hash by name.
				$msg{ $variables{$d->[$nid]}->[$i] } = $d->[$i];
				# Add this same key to the _itemList
				$msg{ '_itemList' }[0]{ $variables{$d->[$nid]}->[$i] } = $d->[$i];
			}
		}
	} else {
		# if no template handles this, just pass it through
		print join('|', @$d)."\n";
	}
	($lastNid, $lastPid) = ($d->[$nid], $d->[$pid]);
}
exit;

