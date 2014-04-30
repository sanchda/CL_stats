#!/usr/bin/perl
# Test in 2014 with whatever the default Ubuntu perl install is
# to install packages:
#
#

use strict;
use warnings;
use Redis;
use Cwd;

use WWW::Mechanize;
use HTML::TokeParser;

# Define the Redis server to be local
my $r = Redis->new( server => '127.0.0.1:6379', debug => 0 , reconnect => 60, every => 5000);

# Make a global WWW::Mechanize context
my $mech = WWW::Mechanize->new();

# A craiglist search requires a location, a category (furniture, electronics,
# housing, jobs, etc), and certain keywords.
my $location = $ARGV[0];
my $category = $ARGV[1];
my $analysis_name = $ARGV[2];

my @keywords;

foreach my $argnum (3..$#ARGV) {
	push(@keywords, $ARGV[$argnum]);
}

# These paremeters being set, the base URL for the search can be constructed.
# Each keyword will be submitted iteratively.
my $base_url = "http://" . $location . ".craigslist.org/search/" . $category . "?query=";

# Also define a url for the proper hit URL (necessary because we need to decimate the array
# of web links we get from the search).
my $base_hit = "/" . $category . "/";


# Loop through the available keywords, looking at the first several pages of search history.
foreach my $cur_keyword(@keywords) {

	# Perform the search, look at the list of links
	my $search_url = $base_url . $cur_keyword;
	sleep 2;
	$mech->get( $search_url );
	my @links = $mech->links();
	my $linklength = @links;

	sleep 4;

	# Check that the given link is a posting, if so navigate and push the parse tree to redis.
	foreach my $cur_link(@links)
	{
		if (index($cur_link->url, $base_hit) != -1 && $cur_link->url ne $base_hit)
		{
  			my $cur_postID = $cur_link->url;
			# Get the post ID from the URL string by taking the base name and splitting out the .html
			($cur_postID) = $cur_postID =~ m#([^/]+)$#;
			my @link_string_array = split('.html',$cur_postID);
			$cur_postID = $link_string_array[0];
			
			# Check whether that particular post ID is in the Redis server
			# If it isn't in, push the 	
			if( $r->sismember($analysis_name . ":postID", $cur_postID) == 0 )
			{
				my @cur_output = parseLink("http://" . $location . ".craigslist.org/" . $cur_link->url);
		
				# Check to make sure that the title is not null
				if( $cur_output[1] ne '' && $cur_output[2] ne '')
				{
					# Good to go.  Let's write to Redis
					$r->sadd($analysis_name . ":postID", $cur_postID);
					$r->set($analysis_name . ":" . $cur_postID . ":title", $cur_output[1]);
					$r->set($analysis_name . ":" . $cur_postID . ":cost", $cur_output[2]);
					$r->set($analysis_name . ":" . $cur_postID . ":location", $cur_output[3]);
					$r->set($analysis_name . ":" . $cur_postID . ":description", $cur_output[4]);
					$r->set($analysis_name . ":" . $cur_postID . ":active", 'yes');
					$r->expire($analysis_name . ":" . $cur_postID  . ":active", 900);  # 15 minutes
					sleep 5;
				}

			}
			# Otherwise, this postID exists.  Each ID has an expiring variable--if it's still set, don't check.
			elsif($r->get($analysis_name . ":" . $cur_postID . ":active") ne 'yes')
			{
				# Not active, so it's safe to check.
				my @cur_output = parseLink("http://" . $location . ".craigslist.org/" . $cur_link->url);
		
				# Check to make sure that the title is not null
				if( $cur_output[1] ne '' && $cur_output[2] ne '')
				{
					# Good to go.  Let's write to Redis
					$r->sadd($analysis_name . ":postID", $cur_postID);
					$r->set($analysis_name . ":" . $cur_postID . ":title", $cur_output[1]);
					$r->set($analysis_name . ":" . $cur_postID . ":cost", $cur_output[2]);
					$r->set($analysis_name . ":" . $cur_postID . ":location", $cur_output[3]);
					$r->set($analysis_name . ":" . $cur_postID . ":description", $cur_output[4]);
					$r->set($analysis_name . ":" . $cur_postID . ":active", 'yes');
					$r->expire($analysis_name . ":" . $cur_postID  . ":active", 900);  # 15 minutes
					sleep 5;
				}
			} # end check link
		}
	} # end link loop
}
exit 0;

# Subroutines

# Parse link
sub parseLink {
	my ($link, $searchname) = $_[0];

	# Make local WWW::Mechanize context
	my $local_mech = WWW::Mechanize->new();

	# Navigate to this page, load it up in TokeParser
	$local_mech->get( $link );
	my $www_stream = HTML::TokeParser->new(\$local_mech->{content});

	# Parse the page from top-to-bottom
	# ASSERT:  page layout hasn't changed since March 2014...

	# First, the posting title, cost, and locationi (first h2 after first aside tag)
	my $tag = $www_stream->get_tag("/aside");

	# <h2 class="postingtitle">
	#  <span class="star"></span>
	#  * * Lodgepole Pine Queen Bed * * - &#x0024;250 (Nampa)
	#</h2>
  	$tag = $www_stream->get_tag("h2");
	# Pull things out of the h2 tag
	my $item_userbody = $www_stream->get_trimmed_text("/h2");

	# Three fields are formatted herein - <title> - $<cost> (<location>).  Parse.
	my @item_userbody_array = split(' - ', $item_userbody);
	my $item_title = $item_userbody_array[0];
	@item_userbody_array = split('\(', $item_userbody_array[1]);
	my $item_cost = $item_userbody_array[0];
	$item_cost = substr($item_cost,1);
	@item_userbody_array = split('\)', $item_userbody_array[1]);
	my $item_location = $item_userbody_array[0];

	# Trim up some excess whitespace
	$item_location =~ s/^\s+//;
	$item_location =~ s/\s+$//;
	$item_cost =~ s/^\s+//;
	$item_cost =~ s/\s+$//;

	# The description is next (fourth section tag)
	$tag = $www_stream->get_tag("section");
	
	# <section id="postingbody">
	my $item_description;
  	$tag = $www_stream->get_tag("section");
  	if ($tag->[1]{id} and $tag->[1]{id} eq "postingbody") {
		# Save the contents
		$item_description = $www_stream->get_trimmed_text("/section");
  	}

	# Get the posting ID
	# <p class="postinginfo">post id: 4404585160</p>
	$tag = $www_stream->get_tag("p");
	my $posting_string = $www_stream->get_trimmed_text("/p");
	my @item_ID_array = split(': ', $posting_string);
	my $item_ID = $item_ID_array[1];

	# Now get the time of post
	# <p class="postinginfo">posted: <time datetime="2014-04-02T17:52:30-0600">2014-04-02  5:52pm</time></p>
	$tag = $www_stream->get_tag("time");
	my $item_time = $tag->[1]{datetime};

#	print $item_ID . "-\n" . $item_title . "-\n" . $item_cost . "-\n" . $item_location . "-\n" . $item_description . "-\n";
	return($item_ID, $item_title, $item_cost, $item_location, $item_description);
}


