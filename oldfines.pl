#!/m1/shared/bin/perl -w
use strict;

=head1 NAME

oldfines.pl

This script remove fines/fees not from August 2018 from the input flie

=head1 USAGE

Read from STDIN output to STDOUT, filtered

=begin code

cat $RPT_DIR/crcnotes.*.inp | perl oldfines.pl

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
use POSIX;

my($crcnote) = new VoyagerCircNotes();
while ($_ = <>) {
	print $_ unless ($crcnote->readLine($_));
}

foreach my $m ($crcnote->byRow()) {
	# for each fine-fee notice
	if ($m->[0]->{'NoticeId'} eq '05') {
		if ($m->[0]->{'FineFeeDate'} =~ m/^08\/..\/2018$/) {
			print $crcnote->getLinesFromMessage($m);
		}
	} else {
		print $crcnote->getLinesFromMessage($m);
	}
}
