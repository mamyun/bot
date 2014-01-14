#!/bin/perl -W

#
# This script implements a bitcoin trading bot on top of the MtGox exchange.
#

use strict;

use POSIX qw(strftime);
use Date::Parse;

use JSON::XS;
use Finance::MtGox;

use MyUtils;
use EMATrader;
use MultiEMATrader;
use MtGoxAccount;

#
# Bot1-RO API key only allows GetInfo.
#

my $Bot1_RO_Key = "7db8503f-9266-4177-a034-90c972ece645";
my $Bot1_RO_Secret = "KcmKfqtzEoEgcuLvuaJK0i+oDv73IEaIPfpLYyFNpUp7YKSYXGKoRAnO/2sUvw+q6i5NB1IkvDM8gUECcTJWdA==";

my $API_Key = $Bot1_RO_Key;
my $API_Secret = $Bot1_RO_Secret;

#
# Trading defaults.
#

my $StartingBTC = 10;

sub TimeStr($);

#
# Instantiate the MtGox interface.
#

my $mtgox = Finance::MtGox->new({
key     => $API_Key,
secret  => $API_Secret
  });
  
#
# Process command-line parameters.
#

my $Args = MyUtils::ProcessCmdLine(\@ARGV);


my $Verbose = $Args->{"-verbose"} || 0;

#
# Initialize account for trading.
#

my $TradingAccount = MtGoxAccount->new(
    Key => $API_Key,
    Secret => $API_Secret,
    BTC => $StartingBTC,
    Verbose => $Verbose);

#
# Create and configure the trader.
#

my $EMAPeriodShort = $Args->{"-EMAPeriodShort"};
my $EMAPeriodLong = $Args->{"-EMAPeriodLong"};

my $Trader;

if ($EMAPeriodShort && $EMAPeriodLong) {
    $Trader = EMATrader->new(
        PeriodShort => $EMAPeriodShort, 
        PeriodLong => $EMAPeriodLong, 
        Account => $TradingAccount);
} else {

    my $RebalancePeriod = $Args->{"-RebalancePeriod"} || 6 * 24 * 15;
    my $RebalanceHistoryMax = $Args->{"-RebalanceHistoryMax"} || 1;

    $Trader = MultiEMATrader->new(
        RebalancePeriod => $RebalancePeriod,
        RebalanceHistoryMax => $RebalanceHistoryMax,
        Account => $TradingAccount, 
        KeepAggregateStats => $Args->{"-AggregateStats"});
}
#
# Open input file, if specified.
#

my $Filepath = $Args->{"-input"};
my $TickerFile;

if ($Filepath) {
    open($TickerFile, $Filepath) or die "Could not open $Filepath: $!";
    
    # Skip the header.
    <$TickerFile>;
}

my @Fields;

print "Time, Price, EMA Short, EMA Long, BuyAndHold USD, EMA_Trader USD, ",
      "EMA_Trader BTC, Buy Count, VolumeBTC, CommissionBTC, Period\n";
      
while (1) {

    #
    # Query private info.
    #
    
#    my $Info = $mtgox->call_auth('generic/private/info');

#    print "\n----------------------\n", JSON::XS->new->pretty(1)->encode($Info), "\n--------------\n";

    my ($Price, $CurrentTime);

    if ($TickerFile) {
        
        my $Line = <$TickerFile>;
        if (!$Line) {last;}
        
        # Timestamp,Open,High,Low,Close,Volume (BTC),Volume (Currency),Weighted Price
        
        @Fields=split /\s*,\s*/, $Line;
        
        $CurrentTime = str2time($Fields[0], "UTC");
        $Price = $Fields[7] + 0;
                
    } else {

        #
        # Get current ticker.
        #
        
        sleep(20);

        my $ticker = $mtgox->call('BTCUSD/ticker_fast');

        #    print "\n----------------------\n", JSON::XS->new->utf8(1)->pretty(1)->encode($ticker), "\n--------------\n";

        if ($ticker && $ticker->{result} eq "success") {
            
            $CurrentTime = int($ticker->{return}{now}) / 1000000;
            $Price = $ticker->{return}{last}{value};

        } else {
            
            print "ERROR: ticker_fast request failed!\n";
            next;
        }
    }
        
    #
    # Pass ticker to trader.
    #
    
    $Trader->NewTicker($Price);

    #
    # Print out stats for this period.
    #
    
    my $ValueUSD = $TradingAccount->GetValueUSD($Price);
    my ($BuyCount, $VolumeBTC, $Commission) = $TradingAccount->GetTradingStats();
    
    printf("%s, %4.2f, %4.2f, %4.2f, %4.2f, %4.2f, %4.2f, %4.2f, %4.2f, %4.2f, %d\n", 
           TimeStr($CurrentTime), $Price, $Trader->GetEMAShort(), 
           $Trader->GetEMALong(), $Price * $StartingBTC, 
           $ValueUSD, $ValueUSD / $Price, $BuyCount, $VolumeBTC, $Commission, 
           ($Trader->GetEMAPeriodLengths())[0]/10);
}

#
# Notify trader that we're done (for any final stats printout).
#

$Trader->Done();

sub TimeStr($) {
    my $TimeInSeconds = shift;
        
    my @TimeFields = gmtime($TimeInSeconds);
    
    # 2013-12-24 01:10:34
    return POSIX::strftime("%Y-%m-%d %H:%M:%S", @TimeFields);
}
