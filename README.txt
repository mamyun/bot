Bitcoin trading bot.

At a high level, the bot concurrently maintains multiple EMA traders and picks
one of them as the active one. The active EMA trader is picked based on its
performance over the last N periods where each period is M days. The EMA traders
as well as the values N and M are picked by running simulations over past data.

First, the EMA traders are picked. The idea is to determine a set of EMA traders
that perform sufficiently well for each 1-month period during e.g. the past year.
"Perform sufficiently well" is based on the score of each EMA trader. The score
is the sum of the count of months for which the trader performs in the top 5%
and the count of months for which the trader performs in the top 10% based on 
the Sortino ratio metric. 

For each month, we pick the EMA trader with the highest score which performs in
the top 5% during that month. That gives us a set of EMA traders which "cover" 
every month. The idea is that each month may have a different price pattern and 
we have a trader that knows how to deal with that.

Next, we need to determine the M and N parameters for the rebalance period and 
the period length. If we simply do that over the entire year, we end up with M
and N that essentially use the right EMA trader at the right time, but overfits
that year's price pattern. To avoid overfitting, we "split" the ticker data such
that the first set starts in Jan and goes through the end of the year. The 
second set starts with Feb, the third set with March, etc while keeping the data
length >= 3 months. 

After splitting the data, we simulate various combinations of M and N over each
data set and aggregate the results into a single result with Min/Max/Avg stats
for each set. We sort the final results by the Avg Sortino ratio over all the 
sets and pick the top performer (most likely) as our M/N pick.

For the 2013 data, the top traders are:
my @EMAPairList = ([222, 552], [144, 210], [72, 81], [102, 300]);
and the best-performing M/N are:
M=1 and N=11.

1. Data collection

We collect Mt. Gox per-trade data and aggregate into 10-minute periods. 
Data can be downloaded from: 
http://api.bitcoincharts.com/v1/csv/

Other ways of acquiring data:
http://www.bitcoincharts.com/about/markets-api/

Once data is downloaded, use data\process_trades.pl to aggregate the data into
10-minute periods. E.g:
perl process_trades.pl -PeriodMin 10 mtgoxUSD-2013-12-26.csv > MtGoxUSD_2011-2013_10min.csv

Afterwards, use a text editor to split the 2011 data from 2012 and so on. In 
practice, I have only used 2013 data so far because the older data may have 
issues with attacks, inconsistency, etc.

2. Pick the EMA traders

To do this, we edit MultiEMATrader.pm slightly to uncomment the call to 
GenerateEMAPairs() such that it will maintain thousands of EMA traders at the 
same time. We specify monthly rebalances. During the run, it will print out
various stats as the Multi EMA trader activates various traders, but we don't
care about that. We care about the output at the very end (to STDERR) which
includes the overall performance of each trader and which ones are selected
according to the criteria as explained above.

perl btc_bot.pl -RebalancePeriod 4320 -RebalanceHistoryMax 1 -input data\MtGoxUSD_2013_10min.csv 2> data\MtGoxUSD_2013_10min_rebalance.csv

3. Split data to start with each month

We want to split/reorganize the data into e.g. 10 pieces such that the next
phase (of determining the rebalanceperiod and history max -- M and N) does not
overfit the overall yearly data. We do that as follows:

for /L %a in (1, 1, 10) DO (
  perl split_data.pl -input MtGoxUSD_2013_10min.csv -start %a -months 12 > monthly\12mo\MtGoxUSD_2013_%a_12mo.csv
)

4. Determine rebalance parameters

To do this, we'll use get_monthly_data.cmd and evaluate.pl to run a bunch of 
simulations with various rebalance parameters (M and N) on the 10 pieces of data
we generated in step 3. 

We essentially want to run the following for each of the months:

perl evaluate.pl -input data\monthly\12mo\MtGoxUSD_2013_1_12mo.csv -rebalance > data\monthly\12mo\MtGoxUSD_2013_1_12mo.csv_results.csv

get_monthly_data.cmd essentially does that (assuming the paths are set properly
in the script):

get_monthly_data.cmd 1 10

However, it's better if we run 4 simulations in parallel to use all CPU cores, 
so it's better to split that into 4:

get_monthly_data.cmd 1 2
get_monthly_data.cmd 3 4
get_monthly_data.cmd 5 7
get_monthly_data.cmd 8 10

After all simulations are done, we'll have 10 results files that need to be 
merged into 1 such that we can look at all the data at once and pick the winner:

perl evaluate2.pl -input data\monthly\12mo\MtGoxUSD_2013_*_12mo.csv_results.csv > data\monthly\12mo\MtGoxUSD_2013_results_all.csv

Finally, determine the best rebalance parameters by mainly looking at the
Avg Sortino Ratio column.

