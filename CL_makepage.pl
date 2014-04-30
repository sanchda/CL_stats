#!/usr/bin/perl

use strict;
use warnings;

use CGI;
use CGI::Carp qw(fatalsToBrowser); # Remove this in production
use Redis;
use List::Util;

my $q = CGI->new;

# Define title to use
my $analysis_name = "local_otto";

# Connect to Redis server
my $r = Redis->new( server => '127.0.0.1:6379', debug => 0, reconnect => 60, every => 5000 );

# Iterate through postIDs and find average price
my @item_prices = $r->smembers($analysis_name . ":postID");
my $mean_value = 0;

foreach my $cur_cost(@item_prices)
{
	$mean_value += $cur_cost;
}

$mean_value = $mean_value/(scalar @item_prices);
print $mean_value;

exit 0;
