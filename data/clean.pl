use strict;
use warnings;

my $LastClose = 0;
while (<>) {

	my @Fields = split /\s*,\s*/;

	if (/Infinity/) {
	  print $Fields[0], ", $LastClose, $LastClose, $LastClose, $LastClose, 0, 0, $LastClose\n";

	  } else {
	
		$LastClose = $Fields[4];
		print $_;
	}
}