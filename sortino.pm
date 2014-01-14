#
# This package maintains the Sortino ratio.
#
# See: http://en.wikipedia.org/wiki/Sortino_ratio
# http://www.futuresmag.com/2013/02/01/sortino-ratio-a-better-measure-of-risk
#
#

package Sortino;

use strict;
use warnings;
use Carp;
use POSIX;

#
# Constructor. 
#    

sub new {
    my ($Class, %args) = @_;
        
    #
    # A "target" return rate can be specified. The Sortino ratio penalizes as 
    # risk those returns that are below this rate. 
    #
    
    my $TargetRate = $args{"TargetRate"} || 0;

    #
    # Create object and initialize fields.
    #
    
    my $Self = {TargetRate => $TargetRate, 
                Count => 0, 
                LastValue => undef,
                DownsideVariance => 0, 
                ReturnRate => 0};
        
    return bless $Self, $Class;
}

sub SetValue {
    my ($Self, $Value) = @_;
    
    #
    # Update stats. The first item is the starting value.
    #
    
    assert($Value > 0);
    
    if ($Self->{Count} > 0) {

        my $Last = $Self->{LastValue};
        my $ReturnRate = ($Value - $Last) / $Last;
        
        $Self->{ReturnRate} += $ReturnRate;
        
        if ($ReturnRate < $Self->{TargetRate}) {
            $Self->{DownsideVariance} += $ReturnRate * $ReturnRate;
        }
    }

    $Self->{LastValue} = $Value;
    $Self->{Count} += 1;
    
    return $Self;
}

sub Query {
    my ($Self) = @_;
    
    if ($Self->{Count} < 2) {
        croak "Sortino::Query() called with no price history!";
    }

    my $Count = $Self->{Count} - 1;
    
    my $AvgReturnRate = $Self->{ReturnRate} / $Count;
    my $DownsideVariance = $Self->{DownsideVariance} / $Count;
    
    if ($DownsideVariance == 0) {
        return 0;
    }
    
    #
    # For negative returns, we'll multiply by variance in order to ensure that 
    # higher downside variance will result in a lower Sortino ratio.
    #
    
    my $RelativeReturn = $AvgReturnRate - $Self->{TargetRate};
    my $Ratio;
    
    if ($RelativeReturn > 0) {
        $Ratio = $RelativeReturn / sqrt($DownsideVariance);
    } else {
        $Ratio = $RelativeReturn * sqrt($DownsideVariance);
    }
    
    return $Ratio;
}

1;
