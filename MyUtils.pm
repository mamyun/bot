package MyUtils;

#
# Places each cmd-line parameter that starts with "-" in a hash with the next
# item as the value (as long as the next item doesn't start with "-"). 
#
# Any remaining items in @ARGV remain (useful for input files and <>).
#

sub ProcessCmdLine {
    my $ArgList = shift;
    
    my $Args = {};
    my $ArgValue;
    my @Temp;
    
    while (@ARGV) {
        my $Arg = shift @ARGV;

        if ($Arg =~ /^-\w+/) {
            
            if (@ARGV && !($ARGV[0] =~ /^-/)) {
                $ArgValue = shift @ARGV;
            } else {
                $ArgValue = 1;
            }
            
            $Args->{$Arg} = $ArgValue;
        } else {
            push @Temp, $Arg;
        }
    }
    
    @ARGV = @Temp;
    
    return $Args;
}

1;