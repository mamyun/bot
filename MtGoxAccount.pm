#!/bin/perl -W
  
#
# This class performs various account operations: buy/sell/info, etc.
#

package MtGoxAccount;

use strict;
use warnings;
use Carp;

use Finance::MtGox;

#
# Constructor. Takes Key and Secret parameters to call MtGox API.
#	

sub new {
	my ($Class, %args) = @_;
	
	if (!(exists($args{Key}) && exists($args{Secret}))) {
		croak "Must specify Key and Secret.";
	}
	
	#
	# Create object and initialize the MtGox object.
	#
	
	my $Self = {};
	$Self->{MtGox} = Finance::MtGox->new({key => $args{Key}, 
                                          secret => $args{Secret}});
	$Self->{BTC} = $args{BTC} || 0;
	$Self->{USD} = $args{USD} || 0;

	$Self->{Commission} = 0;
	$Self->{VolumeBTC} = 0;
	$Self->{BuyCount} = 0;
	
	$Self->{Verbose} = $args{Verbose};

	#
	# Determing commission rate.
	#
	
	$Self->{CommissionRate} = DetermineCommissionRate($Self->{VolumeBTC});
	
	return bless $Self, $Class;
}

sub GetValueUSD {
    my ($Self, $Price) = @_;
    
    return $Self->{BTC} * $Price + $Self->{USD};
}

sub GetTradingStats {
    my ($Self) = @_;
    
    return ($Self->{BuyCount}, $Self->{VolumeBTC}, $Self->{Commission});
}

sub Buy {
	my ($Self, $Price, $Confidence) = @_;
	
	my $USDAmount = $Self->{USD} * $Confidence;
	my $BTCAmount = $USDAmount / $Price;
	
	#
	# Account for commission and update balances/volume.
	#
	
	my $Commission = $BTCAmount * $Self->{CommissionRate};
	
	$Self->{Commission} += $Commission;

	$Self->{BTC} += $BTCAmount - $Commission;
	$Self->{USD} -= $USDAmount;
	
	$Self->{BuyCount} += ($BTCAmount > 0);
	$Self->{VolumeBTC} += $BTCAmount;
	
	#
	# Update commission rate, if necessary.
	#
	
	$Self->{CommissionRate} = DetermineCommissionRate($Self->{VolumeBTC});
	
	if ($USDAmount > 0 && $Self->{Verbose}) {
		print "Bought $BTCAmount BTC at \$$Price.\n";
		print "USD = $Self->{USD}. BTC = $Self->{BTC}\n";
	}
}

sub Sell {
	my ($Self, $Price, $Confidence) = @_;
	
	my $BTCAmount = $Self->{BTC} * $Confidence;
	$Self->{USD} += $BTCAmount * $Price;
	$Self->{BTC} -= $BTCAmount;

	if ($BTCAmount > 0 && $Self->{Verbose}) {
		print "Sold $BTCAmount BTC at \$$Price.\n";
		print "USD = $Self->{USD}. BTC = $Self->{BTC}\n";
	}
}

sub DetermineCommissionRate {
    my $VolumeBTC = shift;
    my @FeeSchedule = ([100, 0.006], [200, 0.0055], [500, 0.0053], [1000, 0.005],
                       [2000, 0.0046], [5000, 0.0043], [10000, 0.004], 
                       [25000, 0.003], [50000, 0.0029], [100000, 0.0028], 
                       [250000, 0.0027], [500000, 0.0026]);
    
    my $Rate = 0.0025;
    
    foreach (@FeeSchedule) {
        if ($VolumeBTC < $_->[0]) {
            $Rate = $_->[1];
            last;
        }
    }

    return $Rate;
}

1;
