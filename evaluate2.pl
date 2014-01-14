#
# This script aggregates evaluation data output by evaluate.pl for multiple
# input files into a single file.
#

use strict;
use warnings;

use File::Basename;
use MyUtils;

#
# Process command line.
#

my $Args = MyUtils::ProcessCmdLine(\@ARGV);

my $InputFiles = $Args->{"-inputs"};
my $KeyColumns = $Args->{"-key_columns"} || 2;

my @FileList = glob($InputFiles);

#
# Go through each file and aggregate contents, using the first 2 fields as the
# unique "key".
#

my %Data;
my @FieldNames;

foreach my $FilePath (@FileList) {
    print STDERR "Processing $FilePath...\n";

    open my $FileHandle, $FilePath or die "Could not open $FilePath: $!\n";

    #
    # Read field names.
    #
    
    my $Header = <$FileHandle>;
    chomp($Header);
    my @Fields = split /\s*,\s*/, $Header;
    
    if (scalar(@FieldNames) == 0) {
        @FieldNames = @Fields;
    } elsif ("@FieldNames" ne "@Fields" ) {
        die "Files don't have the same fields!\n";
    }

    while (<$FileHandle>) {
        chomp;
        @Fields = split /\s*,\s*/;
        
        my $Key = join (", ", @Fields[0 .. $KeyColumns - 1]);
        
        $Data{$Key}{FileData}{$FilePath} = [@Fields[$KeyColumns .. $#Fields]];
    }
    
    close $FileHandle;
}

#
# Calculate aggregates.
#

foreach my $Key (keys %Data) {
    
    my (@Min, @Max, @Avg);
    
    foreach my $FieldList (values %{$Data{$Key}{FileData}}) {
        
        for (my $i = 0; $i < @$FieldList; $i += 1) {
            
            if (!defined ($Min[$i]) || $Min[$i] > $FieldList->[$i]) {
                $Min[$i] = $FieldList->[$i];
            }
            if (!defined ($Max[$i]) || $Max[$i] <= $FieldList->[$i]) {
                $Max[$i] = $FieldList->[$i];
            }
            $Avg[$i] += $FieldList->[$i];
        }
    }
    
    #
    # Commpute average for each field.
    #

    foreach (@Avg) {
        $_ = $_ / scalar (values %{$Data{$Key}{FileData}});
    }
    
    $Data{$Key}->{Min} = [@Min];
    $Data{$Key}->{Max} = [@Max];
    $Data{$Key}->{Avg} = [@Avg];
}

#
# Print everything out.
#
# First the key fields.
#

print join(",", @FieldNames[0 .. $KeyColumns - 1]);

#
# Next come the aggregated stats for each data field.
#

print ", Occurrences";

foreach my $FieldName (@FieldNames[$KeyColumns .. $#FieldNames]) {    
    print ", Min $FieldName, Max $FieldName, Avg $FieldName";
}

#
# Finally, print out the stats from each file we processed.
#

foreach my $FilePath (@FileList) {

    foreach my $FieldName (@FieldNames[$KeyColumns .. $#FieldNames]) {    
        print ", ", basename($FilePath), " $FieldName";
    }
}
print "\n";

#
# Sort the keys before print out.
#

my @Keys = sort {$a cmp $b} keys %Data;

my @PlaceHolders = ("N/A") x (scalar(@FieldNames) - $KeyColumns);

foreach my $Key (@Keys) {
    
    my $KeyData = $Data{$Key};
    my $OccurenceCount = scalar(keys %{$KeyData->{FileData}});
    
    print "$Key, $OccurenceCount"; 
    
    for (my $i = 0; $i < @{$KeyData->{Min}}; $i += 1) {
        
        print ", ", $KeyData->{Min}[$i], ", ", $KeyData->{Max}[$i], ", ", 
              $KeyData->{Avg}[$i];
    }
    
    foreach my $FilePath (@FileList) {

        #
        # If this file did not contain this key, print out placeholders.
        #
        
        my $FieldList = $KeyData->{FileData}{$FilePath};
        
        if (!$FieldList) {
            $FieldList = \@PlaceHolders;
        }

        print ", ", join(", ", @$FieldList);
    }
    
    print "\n";
}