#
# This package implements an EMA trader that concurrently manages multiple EMA
# traders and picks among them periodically based on their recent performance.
#

package MultiEMATrader;

use strict;
use warnings;
use Carp;
use POSIX;

use EMATrader;
use MtGoxAccount;
use Sortino;

my $StartingBTC = 10;

#
# Constructor. Takes the EMA rebalance period parameter and the target account.
#

sub new {
    my ($Class, %args) = @_;
    
    if (!exists($args{RebalancePeriod}) ||
        !exists($args{RebalanceHistoryMax})) 
    {
        croak "Must specify rebelance period and history length!";
    }
        
    if (!exists($args{Account})) {
        croak "Must specify target account!";
    }
    
    #
    # Create object and initialize fields.
    #
    
    my $This = {};

    $This->{RebalancePeriod} = $args{RebalancePeriod};
    $This->{RebalanceHistoryMax} = $args{RebalanceHistoryMax};
    $This->{Account} = $args{Account};
    
    $This->{KeepAggregateStats} = $args{KeepAggregateStats};
    $This->{KeepDetailedStats} = $args{KeepDetailedStats};
    
    $This->{RebalanceStats} = [];
    
    #
    # Initialize the internal EMAs we're going to use along with accounts for
    # simulation.
    #

    $This->{PriceHistory} = [];
    $This->{PriceHistoryMax} = 0;

    # my @EMAPairList = ([126, 390], [180, 420], [156, 204], [144, 384], [21, 99]);
    # my @EMAPairList = GenerateEMAPairs();

    # [180, 480]
    # my @EMAPairList = ([180, 420], [150, 210], [180, 294], [72, 81]);

    my @EMAPairList = ([222, 552], [144, 210], [72, 81], [102, 300]);

    foreach my $EMAPair (@EMAPairList) {

        my $Account = MtGoxAccount->new(
                        Key => "Temp",
                        Secret => "Temp",
                        BTC => $StartingBTC,
                        Verbose => 0);

        my $Trader = EMATrader->new(
                        PeriodShort => $EMAPair->[0], 
                        PeriodLong => $EMAPair->[1], 
                        Account => $Account);
                        
        push @{$This->{TraderList}}, {Trader => $Trader, 
                                      Account => $Account, 
                                      StatsHistory => [[$StartingBTC, 0, 0, 0]],
                                      AggregateStats => [],
                                      RebalanceStats => []};

        #
        # Properly size the price history array such that we can properly jump
        # start EMA calculations instantly when we switch.
        #
        
        if ($This->{PriceHistoryMax} < $EMAPair->[1]) {
            $This->{PriceHistoryMax} = $EMAPair->[1];
        }
    }
    
    #
    # Increase price history some more since the items in the EMA period affect
    # ~86% of the value; the remaining 14% comes from earlier items.
    #
    
    $This->{PriceHistoryMax} *= 4;
    
    #
    # Start out with the first EMA pair.
    #
    
    $This->{CurrentTrader} = EMATrader->new(
                                PeriodShort => $EMAPairList[0][0], 
                                PeriodLong => $EMAPairList[0][1], 
                                Account => $This->{Account});
    $This->{TickerCount} = 0;
        
    return bless $This, $Class;
}

sub GetEMAPeriodLengths {
    my ($Self) = @_;
    
    return $Self->{CurrentTrader}->GetEMAPeriodLengths();
}

sub GetEMAShort {
    my ($Self) = @_;
    
    return $Self->{CurrentTrader}->GetEMAShort();
}

sub GetEMALong {
    my ($Self) = @_;
    
    return $Self->{CurrentTrader}->GetEMALong();
}

sub NewTicker {
    my ($Self, $Price) = @_;

    #
    # Let our current trader process the ticker.
    #
    
    $Self->{CurrentTrader}->NewTicker($Price);
    
    #
    # Forward the ticker notification to each test trader. 
    #
    
    foreach my $Trader (@{$Self->{TraderList}}) {
        
        $Trader->{Trader}->NewTicker($Price);
        
        #
        # Query current stats and store them.
        #

        my $ValueUSD = $Trader->{Account}->GetValueUSD($Price);
        my ($BuyCount, $VolumeBTC, $Commission) = $Trader->{Account}->GetTradingStats();

        #
        # Use pack to significantly reduce memory footprint.
        #

       push @{$Trader->{StatsHistory}}, 
            EncodeStats($ValueUSD / $Price, $Commission);
             
        my $HistoryMax = $Self->{RebalancePeriod} * $Self->{RebalanceHistoryMax};

        if (scalar(@{$Trader->{StatsHistory}}) > $HistoryMax) {
            shift @{$Trader->{StatsHistory}};
        }
    }
    
    #
    # Maintain price history.
    #
    
    push @{$Self->{PriceHistory}}, $Price;
    
    if (scalar (@{$Self->{PriceHistory}}) > $Self->{PriceHistoryMax}) {
        shift @{$Self->{PriceHistory}};
    }

    #
    # Update count and check if we need to rebalance.
    #
    
    $Self->{TickerCount} += 1;
    
    if ($Self->{TickerCount} % $Self->{RebalancePeriod} == 0) {
        
        $Self->Rebalance();
    }

    return;
}

sub EncodeStats {
    return pack('FI', @_);
}

sub DecodeStats {
    return unpack('FI', shift);
}

sub Rebalance {
    my ($Self) = @_;
    
    #
    # Go through the current balance of each trader, compute Sortino Ratio and
    # pick the best.
    #
    
    my @BestEMAPair;
    my $BestMetric = -(10 ** 5);

    foreach my $Trader (@{$Self->{TraderList}}) {
        
        #
        # Stats have already been updated by the caller.
        #

        my $StatsHistory = $Trader->{StatsHistory};
        
        #
        # Compute the Sortino Ratio and other stats.
        #
        
        my $Sortino = Sortino->new();
        my ($Gain, $AvgBTC) = (0, 0);

        foreach my $Stats (@$StatsHistory) {
            my ($BTC, $Commission) = DecodeStats($Stats);
            $Sortino->SetValue($BTC);
            $AvgBTC += $BTC;
        }
        
        $AvgBTC /= scalar(@$StatsHistory);
        
        my $SortinoRatio = $Sortino->Query();
                
        my ($StartValue, undef) = DecodeStats($StatsHistory->[0]);
        my $LastStats = $StatsHistory->[scalar(@$StatsHistory) - 1];
        my ($CurrentValue, $Commission) = DecodeStats($LastStats);

        $Gain = ($CurrentValue - $StartValue) / $StartValue;
        
        #
        # Update long-term stats for this trader.
        #
        
        if ($Self->{KeepAggregateStats}) {
            push @{$Trader->{AggregateStats}}, 
                 [$CurrentValue, $AvgBTC, $Gain, $SortinoRatio, $Commission];
        }

        #
        # Pick the best trader according to our chosen metric.
        #

        if ($SortinoRatio > $BestMetric) {
            $BestMetric = $SortinoRatio;
            @BestEMAPair = $Trader->{Trader}->GetEMAPeriodLengths();
        }
             
        # if ($Gain > $BestMetric) {
            # $BestMetric = $Gain;
            # @BestEMAPair = $Trader->{Trader}->GetEMAPeriodLengths();
        # }
    }
    
    #
    # Remember the price at this rebalance.
    #
    
    my $Price = $Self->{PriceHistory}->[scalar(@{$Self->{PriceHistory}}) - 1];
    push @{$Self->{RebalanceStats}}, $Price;
    
    #
    # If we should keep our current trader, we're done.
    #
    
    my @CurrentEMALengths = $Self->{CurrentTrader}->GetEMAPeriodLengths();
    
    if ($CurrentEMALengths[0] == $BestEMAPair[0] &&
        $CurrentEMALengths[1] == $BestEMAPair[1])
    {
#        print "Staying with ", join ("-", @CurrentEMALengths), "\n";
        return;
    }

#    print "Switching from ", join ("-", @CurrentEMALengths), " to ", 
                             #join("-", @BestEMAPair), "\n";
    
    #
    # Create a new trader. 
    #
    
    $Self->{CurrentTrader} = EMATrader->new(
                                PeriodShort => $BestEMAPair[0], 
                                PeriodLong => $BestEMAPair[1], 
                                Account => $Self->{Account});
    
    #
    # We need to feed a sufficient number of past ticker data to the trader to
    # ensure that it doesn't experience any delays when spinning up its EMAs.
    # The second parameter indicates that these are warmup tickers and that no
    # trades should be performed.
    #
    
    foreach $Price (@{$Self->{PriceHistory}}) {
        $Self->{CurrentTrader}->NewTicker($Price, 1);
    }
    
    return;
}

sub Done {
    my ($Self) = @_;
    
    #
    # Print out stats for each rebalance period for each internal trader.
    #
    
    if (!$Self->{KeepAggregateStats}) {
        return;
    }
    
    #
    # Perform a final rebalance if necessary to update stats.
    #

    if ($Self->{TickerCount} % $Self->{RebalancePeriod}) {
        $Self->Rebalance();
    }
    
    open my $OutFile, ">$Self->{KeepAggregateStats}" or 
                            die "Could not open $Self->{KeepAggregateStats}!";

    print $OutFile "EMAShort, EMALong, Top 5%, Top 10%, Score, Avg Avg BTC, Select";
    
    for (my $i = 1; $i <= scalar(@{$Self->{RebalanceStats}}); $i += 1) {
        print $OutFile ", $i-FinalBTC, $i-AvgBTC, $i-Gain%, $i-Sortino, $i-CommissionBTC";
    }
    print $OutFile "\n";
    
    #
    # For each rebalance period, determine the top 5% and 10% threshold based on 
    # the Sortino ratio.
    #
    
    my $SortinoIndex = 3;
    
    my @RebalancePercentiles;
    
    for (my $i = 0; $i < scalar(@{$Self->{RebalanceStats}}); $i += 1) {
    
        my @SortinoRatios = map {$_->{AggregateStats}[$i][$SortinoIndex]} 
                                @{$Self->{TraderList}};
        my @SortedRatios = sort {$b <=> $a} @SortinoRatios;
        
        my $Top5Percent = $SortedRatios[$#SortedRatios / 20];
        my $Top10Percent = $SortedRatios[$#SortedRatios / 10];
        
        assert($Top5Percent >= $Top10Percent);
        
        $RebalancePercentiles[$i] = [$Top5Percent, $Top10Percent];
    }
    
    #
    # Compute final stats for each trader's performance.
    #

    foreach my $Trader (@{$Self->{TraderList}}) {
        
        my $AggregateStats = $Trader->{AggregateStats};
        
        assert(scalar(@$AggregateStats) == scalar(@RebalancePercentiles));
        
        #
        # Determine the # of rebalance periods during which this trader 
        # performed in the top 5%/10%. 
        #
        # Aggregate stats for each rebalance period:
        # $CurrentValue, $AvgBTC, $Gain, $SortinoRatio, $Commission
        #
        
        my ($Top5Score, $Top10Score, $AvgAvgBTC) = (0, 0, 0);

        for (my $i = 0; $i < scalar(@$AggregateStats); $i += 1) {
            
            my $Stats = $AggregateStats->[$i];

            if ($Stats->[$SortinoIndex] >= $RebalancePercentiles[$i][0]) {
                $Top5Score += 1;
            }
            if ($Stats->[$SortinoIndex] >= $RebalancePercentiles[$i][1]) {
                $Top10Score += 1;
            }
            $AvgAvgBTC += $Stats->[1];
        }
        
        $AvgAvgBTC /= scalar(@$AggregateStats);
        
        #
        # Store these final stats with the trader.
        #
        
        $Trader->{FinalStats} = [$Top5Score, $Top10Score, $AvgAvgBTC];
        $Trader->{Selected} = 0;
    }
    
    #
    # Now, sort each trader by the final stats, first by the total score, then
    # by the Top5 score and finally by the Avg Avg BTC.
    #
    
    my @SortedTraders = sort {
                                my $Top5A = $a->{FinalStats}[0];
                                my $Top5B = $b->{FinalStats}[0];

                                my $TotalA = $Top5A + 
                                             $a->{FinalStats}[1];
                                my $TotalB = $Top5B + 
                                             $b->{FinalStats}[1];
                               
                                if ($TotalB > $TotalA) {
                                    return 1;
                                } elsif ($TotalB < $TotalA) {
                                    return -1;
                                }
                                if ($Top5B > $Top5A) {
                                    return 1;
                                } elsif ($Top5B < $Top5A) {
                                    return -1;
                                }
                                my $AvgA = $a->{FinalStats}[2];
                                my $AvgB = $b->{FinalStats}[2];
                                
                                return $AvgB <=> $AvgA;
                            } @{$Self->{TraderList}};

    #
    # Now, go through each rebalance period and pick the best trader that 
    # performs in the Top 5% for that period. 
    #
    
    for (my $i = 0; $i < @RebalancePercentiles; $i += 1) {
    
        my $Percentiles = $RebalancePercentiles[$i];
        
        my $Trader;
    
        foreach $Trader (@SortedTraders) {

            if ($Trader->{AggregateStats}[$i][$SortinoIndex] >= $Percentiles->[0]) {
                $Trader->{Selected} += 1;
                last;
            }
        }
    }
    
    #
    # Finally, print out all stats for each trader.
    #
                            
    foreach my $Trader (@SortedTraders) {
    
        my $FinalStats = $Trader->{FinalStats};
        my $AggregateStats = $Trader->{AggregateStats};

        print $OutFile join ", ", $Trader->{Trader}->GetEMAPeriodLengths();

        printf($OutFile ", %d, %d, %d, %4.2f, %d", 
                        $FinalStats->[0], $FinalStats->[1],
                        $FinalStats->[0] + $FinalStats->[1],
                        $FinalStats->[2], $Trader->{Selected});
        
        foreach my $Stats (@$AggregateStats) {
            printf($OutFile ", %4.2f, %4.2f, %4.2f, %6.4f, %4.2f", 
                   $Stats->[0], $Stats->[1], $Stats->[2] * 100, $Stats->[$SortinoIndex] * 10000, $Stats->[4]);
        }
        
        print $OutFile "\n";
    }
}

sub GenerateEMAPairs {

    my @EMAPairs = ();

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

    my ($ShortMin, $ShortMax, $ShortDelta) = my @Params1 = (2 * 60, 48 * 60, 30);
    my ($LongMinDelta, $LongMax, $LongDelta) = my @Params2 = (60, 96 * 60, 60);
    my $LongMaxRatio = 8;

    my $InputPeriod = 10;

    #
    # If the caller explicitly specified a set of periods to evaluate, do so.    
    #
    # Scale relevant variables to take into account ticker input period.
    #
    
    ($ShortMin, $ShortMax, $ShortDelta) = map {$_ / $InputPeriod} @Params1;
    ($LongMinDelta, $LongMax, $LongDelta) = map {$_ / $InputPeriod} @Params2;

    for (my $EMAPeriodShort = $ShortMin; 
            $EMAPeriodShort <= $ShortMax; 
            ) 
    {
        for (my $EMAPeriodLong = $EMAPeriodShort + $LongMinDelta;
                $EMAPeriodLong <= $EMAPeriodShort * $LongMaxRatio && 
                $EMAPeriodLong <= $LongMax; 
                )
        {
            push @EMAPairs, [$EMAPeriodShort, $EMAPeriodLong];

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
    
    return @EMAPairs;
}

1;
