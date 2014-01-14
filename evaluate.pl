#
# This script evaluates the trader bot by running it with various parameters
# on the given data file.
#

use strict;
use warnings;
use Carp;

use File::Basename;

use MyUtils;
use Sortino;

#
# Process command line.
#

my $Args = MyUtils::ProcessCmdLine(\@ARGV);

my $FilePath = $Args->{"-input"};

if (!(-e $FilePath)) {
    die "$FilePath does not exist!";
}

#
# Evaluate EMA or rebalance periods based on what caller has provided.
#

my $Results;

if (exists($Args->{"-rebalance"})) { 
    $Results = EvaluateRebalance($Args);

    print "RebalancePeriod, RebalanceHistoryMax, Final BTC, Avg BTC, Commission BTC, SortinoRatio\n";

} else {
    $Results = EvaluateEMA($Args);

    print "EMAPeriodShort, EMAPeriodLong, Final BTC, Avg BTC, Commission BTC, SortinoRatio\n";
}

#
# Print out results.
#

foreach (@$Results) {
    print join(", ", @$_), "\n";
}

sub EvaluateEMA {
    my ($Args) = @_;

    my $EMAPeriodShort = $Args->{"-EMAPeriodShort"};
    my $EMAPeriodLong = $Args->{"-EMAPeriodLong"};

    #
    # The input data has 10-min periods, so we will try short-term EMA periods 
    # between 2hrs and 50hrs in ~30min increments.
    #
    # The long-term EMA periods will go from EMAPeriodShort + 1hr until 
    # EMAPeriodShort * 8 in 1hr increments with a max of 110hrs.
    #

    #
    # EMA ranges in minutes.
    #

    my ($ShortMin, $ShortMax, $ShortDelta) = my @Params1 = (2 * 60, 30 * 60, 30);
    my ($LongMinDelta, $LongMax, $LongDelta) = my @Params2 = (60, 80 * 60, 60);
    my $LongMaxRatio = 8;

    my $InputPeriod = 10;

    #
    # If the caller explicitly specified a set of periods to evaluate, do so.
    #

    if ($EMAPeriodShort && $EMAPeriodLong) {
        $ShortMin = $EMAPeriodShort;
        $ShortMax = $ShortMin;
        $LongMinDelta = $EMAPeriodLong - $EMAPeriodShort;
        $LongMax = $ShortMin + $LongMinDelta;
    } else {
    
        #
        # Scale relevant variables to take into account ticker input period.
        #
        
        ($ShortMin, $ShortMax, $ShortDelta) = map {$_ / $InputPeriod} @Params1;
        ($LongMinDelta, $LongMax, $LongDelta) = map {$_ / $InputPeriod} @Params2;
    }

    my @Results = ();

    for (my $EMAPeriodShort = $ShortMin; 
            $EMAPeriodShort <= $ShortMax; 
            ) 
    {
        for (my $EMAPeriodLong = $EMAPeriodShort + $LongMinDelta;
                $EMAPeriodLong <= $EMAPeriodShort * $LongMaxRatio && 
                $EMAPeriodLong <= $LongMax; 
                )
        {
            print STDERR "Evaluating $EMAPeriodShort/$EMAPeriodLong...";
            my $OutputPath = "output\\" . basename($FilePath) . "_out_$EMAPeriodShort-$EMAPeriodLong.csv";
            
            `perl btc_bot.pl -input $FilePath -EMAPeriodShort $EMAPeriodShort  -EMAPeriodLong $EMAPeriodLong 1> $OutputPath 2>NUL`;
            
            print STDERR "done.";

            #
            # Process the output file and add to results.
            #
            
            my $ResultLine = ProcessOutput($OutputPath,
                                           "$EMAPeriodShort, $EMAPeriodLong");

            push @Results, $ResultLine;

            #
            # For a range of periods, reduce delta to cover better.
            #
            
            if ($EMAPeriodShort >= 40 && $EMAPeriodShort <= 120 &&
                $EMAPeriodLong < 300)
            {
                $EMAPeriodLong += $LongDelta / 2;                
            } elsif ($EMAPeriodLong < 480) {
                $EMAPeriodLong += $LongDelta;
            } else {
                $EMAPeriodLong += $LongDelta * 2;
            }
        }

        #
        # Decrease coverage after 20 hours.
        #
        
        if ($EMAPeriodShort < 120) {
            $EMAPeriodShort += $ShortDelta;
        } else {
            $EMAPeriodShort += $ShortDelta * 2;
        }
    }
    
    return \@Results;
}

sub EvaluateRebalance {
    my ($Args) = @_;

    my $RebalancePeriod = $Args->{"-RebalancePeriod"};
    my $RebalanceHistoryMax = $Args->{"-RebalanceHistoryMax"};

    #
    # Input data has 10-min periods, so we'll calculate the rebalance period
    # in terms of that.
    # We're going to try a range of period length and history lengths.
    #
    # Period lengths in days.
    #

    my ($PeriodMin, $PeriodMax, $PeriodDelta) = my @Params = (1, 30, 0.5);
    my ($HistoryMin, $HistoryMax, $HistoryDelta) = (1, 20, 1);

    my $InputPeriodsPerDay = 6 * 24;

    #
    # If caller explicitly specified a set of parameters to evaluate, do so.
    #

    if ($RebalancePeriod && $RebalanceHistoryMax) {

        $PeriodMin = $RebalancePeriod;
        $PeriodMax = $PeriodMin;
        $HistoryMin = $RebalanceHistoryMax;
        $HistoryMax = $HistoryMin;
    }

    my @Results = ();

    for (my $RebalancePeriod = $PeriodMin; 
            $RebalancePeriod <= $PeriodMax; 
            $RebalancePeriod += $PeriodDelta) 
    {
        for (my $RebalanceHistoryMax = $HistoryMin;
                $RebalanceHistoryMax <= $HistoryMax;
                $RebalanceHistoryMax += $HistoryDelta)
        {
			#
			# No point in looking back more than 2 months.
			#
			
			if ($RebalancePeriod * $RebalanceHistoryMax > 60) {
				last;
			}

            print STDERR "Evaluating $RebalancePeriod/$RebalanceHistoryMax...";
            my $OutputPath = "output\\" . basename($FilePath) . 
                             "_rb_out_$RebalancePeriod-$RebalanceHistoryMax.csv";
            
			my $PeriodInInputPeriods = $RebalancePeriod * $InputPeriodsPerDay;
            `perl btc_bot.pl -input $FilePath -RebalancePeriod $PeriodInInputPeriods  -RebalanceHistoryMax $RebalanceHistoryMax 1> $OutputPath 2>NUL`;
            
            print STDERR "done.";
            
            #
            # Process the output file and add to results.
            #
            
            my $ResultLine = ProcessOutput($OutputPath,
                                           "$RebalancePeriod, $RebalanceHistoryMax");

            push @Results, $ResultLine;
        }
    }
    
    return \@Results;
}

sub ProcessOutput {
    my ($OutputPath, $Key) = @_;

    #
    # Open, read and process the last line of output to get the resulting BTC.
    #
    # File has the following fields:
    # Time, Price, EMA Short, EMA Long, BuyAndHold USD, EMA_Trader USD, EMA_Trader BTC, Buy Count, VolumeBTC, CommissionBTC
    #
    
    open (my $OutFile, $OutputPath) or die "Could not open $OutputPath:$!";
    <$OutFile>;
    
    my ($Count, $BTC, $TotalBTC, $CommissionBTC) = (0, 0, 0, 0);
	my @Fields;
	my $Sortino = Sortino->new();

    while (<$OutFile>) {
        chomp; 
        @Fields = split /\s*,\s*/;
        
        $Count += 1;
        $BTC = $Fields[6] + 0;
        $TotalBTC += $BTC;
		
		#
		# Update the Sortino stats.
		#
		
    	$Sortino->SetValue($BTC);

        $CommissionBTC = $Fields[9] + 0;
    }
	
    my $AvgBTC = $TotalBTC / $Count;
	my $SortinoRatio = $Sortino->Query();
	    
    printf(STDERR " Final: %4.2f, Avg: %4.2f, Comm: %4.2f, Sortino: %6.4f\n", 
		   $BTC, $AvgBTC, $CommissionBTC, $SortinoRatio);
    
    return [$Key, $BTC, $AvgBTC, $CommissionBTC, $SortinoRatio];
}