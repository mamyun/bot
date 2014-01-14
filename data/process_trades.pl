#
# This script processes a CSV file containing bitcoin trades and aggregates them
# into N-minute buckets as specified on the command line. The input file has the
# following fields:
# UNIX time, Price, Volume
#

use strict;
use warnings;

use DateTime;

use MyUtils;

#
# Process command line.
#

my $Args = MyUtils::ProcessCmdLine(\@ARGV);

#
# Determine period.
#

my $PeriodLength = $Args->{"-PeriodMin"} || 60;

if ($PeriodLength > 60) {
    die "Periods longer than 60 minutes are not supported!";
}

$PeriodLength *= 60;

my $PeriodStart = 0;
my $CurrentTime;
my ($LastPrice, $BTC);
my ($VolumeUSD, $VolumeBTC) = (0, 0);
my ($Open, $High, $Low) = (0, 0, 0);

while (<>) {

	my @Fields = split /\s*,\s*/;
    
    #
    # Fields:
    # UNIX time, Price, VolumeBTC
    #
    
    $CurrentTime = $Fields[0] + 0;
    
    #
    # Did we start a new period?
    #
    
    while ($CurrentTime >= $PeriodStart + $PeriodLength) {
        
        if ($PeriodStart == 0) {
            
            $PeriodStart = RoundDownToPeriod($CurrentTime, $PeriodLength);
            last;
            
        } else {
            
            #
            # Print last period's stats with the following fields:
            # Timestamp,Open,High,Low,Close,Volume (BTC),Volume (Currency),Weighted Price            
            #
            
            my $Time = DateTime->from_epoch(epoch => $PeriodStart);
            my $TimeStr = $Time->strftime("%Y-%m-%d %H:%M");
            
            if ($VolumeBTC) {
            
                print "$TimeStr, $Open, $High, $Low, $LastPrice, ", 
                      "$VolumeBTC, $VolumeUSD, ", $VolumeUSD / $VolumeBTC, "\n";

                ($Open, $High, $Low, $VolumeBTC, $VolumeUSD) = (0, 0, 9999999, 0, 0);
            } else {
                
                print "$TimeStr, $LastPrice, $LastPrice, $LastPrice, $LastPrice, ", 
                      "0, 0, ", $LastPrice, "\n";
            }
            
            $PeriodStart += $PeriodLength;
        }
    }
    
    #
    # Accumulate stats.
    #
    
    $LastPrice = $Fields[1] + 0;
    
    if (!$Open) {
        $Open = $LastPrice;
    }
    
    if ($LastPrice > $High) {
        $High = $LastPrice;
    }
    
    if ($LastPrice < $Low) {
        $Low = $LastPrice;
    }
    
    $BTC = $Fields[2] + 0;
    $VolumeBTC += $BTC;
    $VolumeUSD += $BTC * $LastPrice;
}

sub RoundDownToPeriod {
    my ($Timestamp, $Period) = @_;
    
    my $Time = DateTime->from_epoch(epoch => $Timestamp);
        
    #
    # Round seconds down by the Period.
    #
    
    my $Seconds = $Time->minute() * 60 + $Time->second();
        
    $Time->subtract(seconds => $Seconds % $Period);
        
    return $Time->epoch();
}