#
# This file creates various trading strategies.
#

package EMATrader;

use strict;
use warnings;
use Carp;
use POSIX;

use Math::Business::EMA;
use Math::Business::MACD;

use MtGoxAccount;

#
# Constructor. Takes PeriodShort and PeriodLong parameters and
# the target account.
#    

sub new {
    my ($Class, %args) = @_;
    
    if (!(exists($args{PeriodShort}) && exists($args{PeriodLong})) ||
        $args{PeriodShort} >= $args{PeriodLong})
    {
        croak "Must specify Period1 and Period2 where Period1 < Period2!";
    }
    
    if (!exists($args{Account})) {
        croak "Must specify target account!";
    }
    
    #
    # Create object and initialize fields.
    #
    
    my $This = {};
    
    $This->{PeriodLengths} = [$args{PeriodShort}, $args{PeriodLong}];

    $This->{EMAShort} = Math::Business::EMA->new($args{PeriodShort});
    $This->{EMALong} = Math::Business::EMA->new($args{PeriodLong});
    
    # $This->{MACD} = Math::Business::MACD->new($args{PeriodLong}, 
                                              # $args{PeriodShort},
                                              # int($args{PeriodShort} * 0.75));

    $This->{Account} = $args{Account};

    return bless $This, $Class;
}

sub GetEMAPeriodLengths {
    my ($Self) = @_;
    
    return @{$Self->{PeriodLengths}};
}

sub GetEMAShort {
    my ($Self) = @_;
    
    my $EMA = $Self->{EMAShort}->query() || 0;
    
#    assert(($EMA == 0) || ($EMA == $Self->{MACD}->query_fast_ema()));
    
    return $EMA;
}

sub GetEMALong {
    my ($Self) = @_;
    
    my $EMA = $Self->{EMALong}->query() || 0;
    
#    assert(($EMA == 0) || ($EMA == $Self->{MACD}->query_slow_ema()));
    
    return $EMA;
}

sub NewTicker {
    my ($Self, $Price, $Warmup) = @_;

    #
    # If the EMAs have not stabilized yet, don't perform any trading.
    #
    
    my $TradeOK = ($Self->GetEMALong() > 0) && !$Warmup;
        
    #
    # Update EMAs.
    #
    
    $Self->{EMAShort}->insert($Price);
    $Self->{EMALong}->insert($Price);
#    $Self->{MACD}->insert($Price);
        
    #
    # If short-term EMA is above the long-term EMA, it's a buy signal. Otherwise, 
    # it's a sell signal.
    #
    # In practice, the account will only perform a trade when the values cross,
    # but we call it everytime to more easily handle the case of the multi-EMA
    # trader's switch scenario.
    #

    my $Direction = 1; #$Self->{MACD}->query_histogram();
    
    if ($TradeOK && defined($Direction)) {
    
        if ($Self->GetEMAShort() > $Self->GetEMALong()) {
                        
            $Self->{Account}->Buy($Price, 1);

        } else {
            
            $Self->{Account}->Sell($Price, 1);
        }
        

        # if ($Direction > 0) {
            # $Self->{Account}->Buy($Price, 1);
        # } else {
            # $Self->{Account}->Sell($Price, 1);
        # }

    }

    return;
}

1;
