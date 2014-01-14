#
# This script splits the input aggregated trade data into monthly pieces.
#
# Usage: split_data.pl -start 2013-03 -months 6 -input trades.csv
#

use strict;
use warnings;

use DateTime;
use Date::Parse;

use MyUtils;

#
# Process command line.
#

my $Args = MyUtils::ProcessCmdLine(\@ARGV);

my $FilePath = $Args->{"-input"};

if (!(-e $FilePath)) {
    die "$FilePath does not exist!";
}

open (my $InputFile, $FilePath) or die "Could not open $FilePath: $!";

#
# Determine where to start and how many months we want.
#

my $Start = $Args->{"-start"};
my $MonthCount = $Args->{"-months"};

my $StartTime = DateTime->from_epoch(epoch => str2time("$Start-01", "UTC"));

my $EndTime = $StartTime->clone();
$EndTime->add(months => $MonthCount);

#
# Process the input file.
#

while (<$InputFile>) {
    
    my @Fields = split /\s*,\s*/;
    my $ItemTime = DateTime->from_epoch(epoch => str2time($Fields[0], "UTC"));
        
    if (DateTime->compare($ItemTime, $StartTime) < 0) {
        next;
    }
    
    if (DateTime->compare($ItemTime, $EndTime) >= 0) {
        last;
    }
    
    print;
}