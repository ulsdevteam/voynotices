#!/m1/shared/bin/perl -w
use strict;

=head1 NAME

postprocess.pl

This script will send an email extacting fine/fee information from the circulation notices

=head1 USAGE

Read from STDIN, process notice line(s), send email to address provided.

=begin code

cat $RPT_DIR/crcnotes.*.inp | perl postprocess.pl my.email@address.tld

=end code

=head1 COPYRIGHT AND LICENSE

Copyright (c) University of Pittsburgh

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

=cut

use FindBin;
use lib "$FindBin::Bin";
use VoyagerCircNotes;
use Sys::Hostname;
use Email::Sender::Simple;
use Email::MIME;
use Email::Address::XS;
use Mojo::Template;
use POSIX;

my($email) = shift @ARGV;
my(@emails);
if ($email) {
	foreach my $e (Email::Address::XS->parse($email)) {
		if ($e->is_valid()) {
			push @emails, $e;
		} else {
			warn 'Invalid address: '.$e->address();
		}
	}
}
die 'The recipient email(s) must be provided as the first parameter' unless (@emails);
$email = join(', ', @emails);
my($template_file) = $FindBin::Bin.'/finefee.tmpl';
die 'The file '.$template_file.' is missing' unless (-r $template_file);

my($crcnote) = new VoyagerCircNotes();
while ($_ = <>) {
	print $_ unless ($crcnote->readLine($_));
}

my($counter) = 0;
my($csv) = '';
my(@csvFields) = ('LastName', 'FirstName', 'Email', 'ItemTitle', 'ItemId', 'FineFeeDate', 'FineFeeAmount', 'FineFeeBalance', 'PreviouslyBilled', 'TotalFinesFees');
foreach my $m ($crcnote->byRow()) {
	# for each fine-fee notice
	if ($m->[0]->{'NoticeId'} eq '05') {
		for my $f (@csvFields) {
			$csv .= quote_csv($m->[0]->{$f}).($f eq $csvFields[$#csvFields] ? "\n" : ',');
		}
	}
}
if ($csv) {
	my($failureMessage) = '';
	my($csvHeader) = '';
	for my $f (@csvFields) {
		$csvHeader .= quote_csv($f).($f eq $csvFields[$#csvFields] ? "\n" : ',');
	}
	$csv = $csvHeader.$csv;
	my($t) = Mojo::Template->new();
	$t->vars(1);
	my($render) = $t->render_file($template_file, { 'email' => $email } );
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
			# Markdown will probably give a more readable interpretation, if available
			my(@moduleErrors);
			eval 'use HTML::WikiConverter::Markdown';
			@moduleErrors = $@ if ($@);
			eval 'use HTML::WikiConverter';
			@moduleErrors = $@ if ($@);
			if (@moduleErrors) {
				# HTML::FormatText loses all formatting, but is a good fallback
				eval 'use HTML::FormatText';
				if (!$@) {
					$body = HTML::FormatText->format_string($body);
				}
			} else {
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
		# add the CSV
		push @parts, Email::MIME->create(
			'body_str' => $csv,
			'attributes' => {
				'content_type' => 'text/csv',
				'disposition' => 'attachment',
				'encoding' => 'base64',
				'charset' => $characterSet,
				'filename' => 'finefee-'.POSIX::strftime('%Y-%m-%d', localtime()).'.csv',
			}
		);
		# place the parts in a message
		my($email) = Email::MIME->create(
			'header_str' => $mailHeader,
			'parts' => \@parts,
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
	}
}

sub quote_csv {
	my($var) = shift;
	my($wrap) = 0;
	if ($var =~ m/"/) {
		$wrap = 1;
		$var =~ s/"/""/g;
	}
	if ($var =~ m/,/) {
		$wrap = 1;
	}
	return $wrap ? '"'.$var.'"' : $var;
}

sub trim {
	my($var) = shift;
	$var =~ s/\s+$//;
	$var =~ s/^\s+//;
	return $var;
}

__END__

