#!/m1/shared/bin/perl -w
use strict;

use VoyagerCircNotes;
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

