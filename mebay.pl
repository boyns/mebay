#!/usr/bin/perl
#
# $Id: mebay.pl,v 1.7 2000/07/10 19:28:36 boyns Exp $
#
# Copyright (C) 2000 Gargola Software
#
# MeBay is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# MeBay is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with MeBay; see the file COPYING.  If not, write to the
# Free Software Foundation, Inc.,
# 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.
#

use strict;
use DB_File;
use Socket;
use FileHandle;
use Getopt::Long;
use Time::Local;
use Gtk;
eval "require Gtk::Gdk::ImlibImage";
require 'ctime.pl';

my $version = "0.3.1";
my $debug = 0;
my $mebay_dir = "$ENV{'HOME'}/.mebay";
my $user_agent = "Mozilla/4.5 [en] (X11; I; Linux 2.2.14 i686; Nav)";
my $http_proxy_host = undef;
my $http_proxy_port = undef;

my $signed_in = 0;
my %ebay;
my %mybid_items;
my %mywatch_items;
my %labels;
my %buttons;

print copyleft();

if (defined($ENV{'http_proxy'}))
{
    if ($ENV{'http_proxy'} =~ m,http://([^/:]+)(:\d+)?(/.*)?,)
    {
	my ($host, $port, $path) = ($1, $2, $3);
	$port =~ s/://;
	$port = 80 unless $port;

	$http_proxy_host = $host;
	$http_proxy_port = $port;

	print "using proxy $http_proxy_host:$http_proxy_port\n" if $debug;
    }
}

Gtk->init;
Gtk::Gdk::ImlibImage->init;

mkdir($mebay_dir, 0700);

#my $root_win = Gtk::Gdk::Window->new_foreign(Gtk::Gdk->ROOT_WINDOW());

my $mw = new Gtk::Window('toplevel');
$mw->set_title("MeBay");
$mw->border_width(0);

$mw->signal_connect("destroy" => \&Gtk::main_quit);
$mw->signal_connect("delete_event" => \&Gtk::false);

my $style = Gtk::Widget->get_default_style;
$mw->realize;

my $red_color = $mw->window->get_colormap->color_alloc( { red => 65000, green => 0, blue => 0 } );
my $green_color = $mw->window->get_colormap->color_alloc( { red => 0, green => 33287, blue => 0 });
my $blue_color = $mw->window->get_colormap->color_alloc( { red => 0, green => 0, blue => 65000 } );
my $black_color = $mw->window->get_colormap->color_alloc( { red => 0, green => 0, blue => 0 } );
my $white_color = $mw->window->get_colormap->color_alloc( { red => 65000, green => 65000, blue => 65000 } );

my $box1 = new Gtk::VBox(0, 0);
$mw->add($box1);
$box1->show;

my ($mybid_clist, $mybid_page) = create_mybid_page();
my ($mywatch_clist, $mywatch_page) = create_mywatch_page();
my ($search_clist, $search_page) = create_search_page();
my ($bidder_clist, $bidder_page) = create_bidder_page();
my ($seller_clist, $seller_page) = create_seller_page();
my ($completed_clist, $completed_page) = create_completed_page();
my ($purchased_clist, $purchased_page) = create_purchased_page();
my ($sold_clist, $sold_page) = create_sold_page();
#my ($prefs_page) = create_prefs_page();

$search_clist->signal_connect('select_row', \&display_item);
$mywatch_clist->signal_connect('select_row', \&display_item);
$mybid_clist->signal_connect('select_row', \&display_item);
$bidder_clist->signal_connect('select_row', \&display_item);
$seller_clist->signal_connect('select_row', \&display_item);
$completed_clist->signal_connect('select_row', \&display_item);
$purchased_clist->signal_connect('select_row', \&display_item);
$sold_clist->signal_connect('select_row', \&display_item);

my %item_search;
my %bidder_search;
my %seller_search;
my %completed_search;

#my $hbox = new Gtk::HBox(0, 0);
#$hbox->show;
#my $time_label = new Gtk::Label("");
#$time_label->show;
#$hbox->pack_start($time_label, 0, 1, 5);
#my $sync = new Gtk::Button("Sync");
#$sync->signal_connect("clicked", sub { update_ebay_time(1); });
#$sync->show;
#$hbox->pack_start($sync, 0, 1, 5);
#$box1->pack_start($hbox, 0, 1, 5);

my $myebay_notebook = new Gtk::Notebook;
$myebay_notebook->set_tab_pos(-top);
$myebay_notebook->border_width(5);
$myebay_notebook->show;
$myebay_notebook->append_page($mybid_page, new Gtk::Label("Items I'm Bidding On"));
$myebay_notebook->append_page($mywatch_page, new Gtk::Label("Items I'm Watching"));

my $find_notebook = new Gtk::Notebook;
$find_notebook->set_tab_pos(-top);
$find_notebook->border_width(5);
$find_notebook->show;
$find_notebook->append_page($search_page, new Gtk::Label("Search"));
$find_notebook->append_page($bidder_page, new Gtk::Label("By Bidder"));
$find_notebook->append_page($seller_page, new Gtk::Label("By Seller"));
$find_notebook->append_page($completed_page, new Gtk::Label("Completed Items"));

my $manage_notebook = new Gtk::Notebook;
$manage_notebook->set_tab_pos(-top);
$manage_notebook->border_width(5);
$manage_notebook->show;
$manage_notebook->append_page($purchased_page, new Gtk::Label("Items Purchased"));
$manage_notebook->append_page($sold_page, new Gtk::Label("Items Sold"));

my $feedback_page = create_feedback_page();
my $about_page = create_about_page();

my $notebook = new Gtk::Notebook;
$notebook->set_tab_pos(-top);
$notebook->border_width(5);
$notebook->show;
$notebook->append_page($myebay_notebook, new Gtk::Label("My eBay"));
$notebook->append_page($find_notebook, new Gtk::Label("Find Items"));
$notebook->append_page($manage_notebook, new Gtk::Label("Manage Items"));
$notebook->append_page($feedback_page, new Gtk::Label("View Feedback"));
#$notebook->append_page($prefs_page, new Gtk::Label("Preferences"));
$notebook->append_page($about_page, new Gtk::Label("About"));

$box1->pack_start($notebook, 1, 1, 0);

#my $i;
#my %month_hash;
#foreach ('Jan','Feb','Mar','Apr','May','Jun', 'Jul','Aug','Sep','Oct','Nov','Dec')
#{
#    $month_hash{$_} = $i++;
#}

#my $timer_interval = 1000;
#my $time_delta = 0;
#my $timer;
#update_ebay_time(1);

my @purchased_states =
(
 "contact seller",
 "payment sent",
 "payment received",
 "item sent",
 "feedback received",
 "item received",
 "feedback sent",
 "complete"
);

my @sold_states =
(
 "contact buyer",
 "payment received",
 "payment cashed",
 "feedback sent",
 "item sent",
 "item received",
 "feedback received",
 "complete"
);

my $purchased_x = tie my %purchased_db, "DB_File", "$mebay_dir/purchased.db", O_CREAT|O_RDWR, 0600;
my $sold_x = tie my %sold_db, "DB_File", "$mebay_dir/sold.db", O_CREAT|O_RDWR, 0600;
my $notes_x = tie my %notes_db, "DB_File", "$mebay_dir/notes.db", O_CREAT|O_RDWR, 0600;
#my $prefs_x = tie my %prefs_db, "DB_File", "$mebay_dir/prefs.db", O_CREAT|O_RDWR, 0600;

$mw->show;
Gtk->main;

sub signin
{
    my ($userid, $pass, $callback) = @_;
    my (%hash, $html);

    $ebay{'cookie'} = "";

    $html = get("cgi1.ebay.com", 80, "/aw-cgi/eBayISAPI.dll?MyEbayLogin");
    $hash{'MfcISAPICommand'} = "MyEbay";
    $hash{'first'} = "Y";
    $hash{'userid'} = $userid;
    $hash{'pass'} = $pass;
    $hash{'dayssince'} = 2;
    $hash{'sellerSort'} = 3;
    $hash{'bidderSort'} = 3;
    $html = post("cgi1.ebay.com", 80, "/aw-cgi/eBayISAPI.dll", \%hash);
    if ($html =~ m,userid=([^&]+)&pass=([^&]+)&,)
    {
	$ebay{'userid'} = $1;
	$ebay{'ciphertext'} = $2;
	$ebay{'realpass'} = $pass;
	$signed_in++;
    }

    &$callback if $callback;
}

# sub old_signin
# {
#     my ($userid, $pass, $callback) = @_;
#     my %hash;

#     $hash{'userid'} = $userid;
#     $hash{'pass'} = $pass;
#     $hash{'MfcISAPICommand'} = "SignInWelcome";
#     my $html = post("cgi1.ebay.com", 80, "/aw-cgi/eBayISAPI.dll", \%hash);

#     if ($html =~ /Set-Cookie: ([^\n]+)/i)
#     {
# 	$ebay{'cookie'} = $1;
#         $html = get("cgi1.ebay.com", 80, "/aw-cgi/eBayISAPI.dll?MyEbayLogin");

# 	# <input type="hidden" name="pass" value="XXX">
# 	if ($html =~ m,name\s*=\s*\"pass\"\s+value\s*=\s*\"([^\"]+)\",)
# 	{
# 	    $pass = $1;
# 	    $hash{'MfcISAPICommand'} = "MyEbay";
# 	    $hash{'first'} = "Y";
# 	    $hash{'userid'} = $userid;
# 	    $hash{'pass'} = $pass;
# 	    $hash{'dayssince'} = 2;
# 	    $hash{'sellerSort'} = 3;
# 	    $hash{'bidderSort'} = 3;
# 	    $html = post("cgi1.ebay.com", 80, "/aw-cgi/eBayISAPI.dll", \%hash);
# 	    if ($html =~ m,userid=([^&]+)&pass=([^&]+)&,)
# 	    {
# 		$ebay{'userid'} = $1;
# 		$ebay_pass = $2;
# 	    }
# 	}
#     }

#     &$callback if $callback;
# }

sub watch
{
    my ($item) = @_;

    if (!$signed_in)
    {
	create_signin_window(sub {watch($item)});
	return;
    }

    my $key;
    my $html = get("cgi1.ebay.com", 80, "/aw-cgi/eBayISAPI.dll?MakeTrack&item=$item");

    if ($html =~ m,name\s*=\s*key\s+value\s*=\s*\"([^\"]+)\",)
    {
	$key = $1;
    }

    if ($key)
    {
	my %hash;

	$hash{'MfcISAPICommand'} = "AcceptTrack";
	$hash{'userid'} = $ebay{'userid'};
	$hash{'pass'} = $ebay{'realpass'};
	$hash{'item'} = $item;
	$hash{'key'} = $key;
	$html = post("cgi1.ebay.com", 80, "/aw-cgi/eBayISAPI.dll", \%hash);
    }
}

sub nowatch
{
    # have to be signed in to get here
    my @items = @_;
    my %hash;

    $hash{'MfcISAPICommand'} = "RemoveTrackedItems";
    $hash{'userid'} = $ebay{'userid'};
    $hash{'pass'} = $ebay{'ciphertext'};

    my $i = 1;
    foreach my $item (@items)
    {
	$hash{"checkbox" . $i++} = $item;
    }

    my $html = post("cgi1.ebay.com", 80, "/aw-cgi/eBayISAPI.dll", \%hash);

    foreach (@items)
    {
	delete $mywatch_items{$_};
	my $row = find_clist_item($mywatch_clist, $_);
	$mywatch_clist->remove($row) if $row != -1;
    }
}


#sub sync_ebay_time
#{
#    my $html = get("cgi3.ebay.com", 80, "/aw-cgi/eBayISAPI.dll?TimeShow");
#    my $now = time;
#    if ($html =~ m!<p>At the tone, the time will be... <b>([^>]+)</b><br>!)
#    {
#	$_ = $1;
#	/(\w+),\s+(\w+)\s+(\d+),\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\w+)/;
#	my $time = timelocal($7, $6, $5, $3, $month_hash{$2}, $4 - 1900);
#	$time_delta = $now - $time;
#    }
#}

# sub update_ebay_time
# {
#     my ($sync) = @_;

#     if ($sync)
#     {
# 	Gtk->timeout_remove($timer) if $timer;
# 	sync_ebay_time();
# 	$timer = Gtk->timeout_add($timer_interval, \&update_ebay_time);
#     }
#     else
#     {
# 	$ebay_time += ($timer_interval / 1000);
#     }

#     my $s = ctime(time + $time_delta);
#     chomp $s;
#     $time_label->set_text($s);

#     return 1;
# }

sub set_row_color
{
    my ($clist, $row, $item, $bid) = @_;
    my $maxbid = undef;

    $bid =~ s/^\$//g;

    if (defined($mybid_items{$item}))
    {
	$maxbid = $mybid_items{$item};
    }

    if (defined($maxbid))
    {
	# winning
	if ($bid <= $maxbid)
	{
	    $clist->set_foreground($row, $green_color);
	}
	# losing
	else
	{
	    $clist->set_foreground($row, $red_color);
	}
    }
    elsif (defined($mywatch_items{$item}))
    {
	# watching
	$clist->set_foreground($row, $blue_color);
    }
}

sub update_mybid
{
    my ($clist) = @_;

    if (!$signed_in)
    {
	create_signin_window(sub {update_mybid($clist)});
	return;
    }

    my @keys = qw(item startbid bid maxbid quant nbids start end timeleft);
    my $nkeys = scalar(@keys);
    my ($html, $td, $anchor, $row);
    my $index = -1;
    my %hash;

    $html = get("cgi1.ebay.com", 80, "/aw-cgi/ebayISAPI.dll?MyeBayItemsBiddingOn&userid=$ebay{'userid'}&pass=$ebay{'ciphertext'}&first=N&sellerSort=3&bidderSort=3&dayssince=2&p1=0&p2=0&p3=0&p4=0&p5=0");

    $clist->clear();

    %mybid_items = ();

    while ($html =~ m,<td[^>]*>(.+?)</td>,igs)
    {
	$td = $1;
	if ($td =~ m,<a[^>]+>([^<]+)</a>,i)
	{
	    $anchor = $1;
	    #print "anchor = $anchor\n";
	    #last if $anchor =~ /items\s+i\'m\s+watching/i;
	    next;
	}
	$td =~ s/<[^>]+>//g;
	$td =~ s/&nbsp;//g;

	if ($td =~ /^time left$/i)
	{
	    $index = 0;
	    next;
	}
	next if $index < 0;
	last if $td =~ /^item$/i;
	last if $td =~ /^items\s+i\'m\s+watching$/i;

	$hash{$keys[$index++]} = $td;

	if ($index == $nkeys)
	{
	    $hash{title} = $anchor;

	    $clist->append($hash{item}, $hash{title}, $hash{startbid}, $hash{bid},
			   $hash{maxbid}, $hash{nbids}, $hash{timeleft}, $hash{end});

	    my $bid = $hash{bid};
	    $bid =~ s/^\$//g;
	    my $maxbid = $hash{maxbid};
	    $maxbid =~ s/^\$//g;

	    $mybid_items{$hash{item}} = $maxbid;

	    set_row_color($clist, $row, $hash{item}, $hash{bid});

	    $row++;

	    $index = 0;
	    $anchor = "";
	    %hash = ();
	}
    }
}

sub update_mywatch
{
    my ($clist) = @_;

    if (!$signed_in)
    {
	create_signin_window(sub {update_mywatch($clist)});
	return;
    }

    my @keys = qw(item bid nbids timeleft);
    my $nkeys = scalar(@keys);
    my ($html, $td, $anchor, $row);
    my $index = -1;
    my %hash;

    $html = get("cgi1.ebay.com", 80, "/aw-cgi/ebayISAPI.dll?MyeBayItemsBiddingOn&userid=$ebay{'userid'}&pass=$ebay{'ciphertext'}&first=N&sellerSort=3&bidderSort=3&dayssince=2&p1=0&p2=0&p3=0&p4=0&p5=0&watchSort=3");

    $clist->clear();

    %mywatch_items = ();

    while ($html =~ m,<td[^>]*>(.+?)</td>,igs)
    {
	$td = $1;
	if ($td =~ m,<a[^>]+>([^<]+)</a>,i)
	{
	    $anchor = $1;
	    next;
	}
	$td =~ s/<[^>]+>//g;
	$td =~ s/&nbsp;//g;

	next if $td =~ /^$/; # checkbox
	next if $td =~ /bid now/i;

	if ($td =~ /^bid onthis item$/i)
	{
	    $index = 0;
	    next;
	}

	next if $index < 0;
	last if $td =~ /^item$/i;

	$hash{$keys[$index++]} = $td;

	if ($index == $nkeys)
	{
	    $hash{title} = $anchor;
	    $clist->append($hash{item}, $hash{title}, $hash{bid},
			   $hash{nbids}, $hash{timeleft});

	    $mywatch_items{$hash{item}}++;

	    set_row_color($clist, $row, $hash{item}, $hash{bid});

	    $row++;

	    $index = 0;
	    $anchor = "";
	    %hash = ();
	}
    }
}

sub update_search
{
    my ($clist, $type, $pattern, $skip) = @_;
    my @keys = qw(item price bids ends);
    my $nkeys = scalar(@keys);
    my ($html, $td, $anchor, $row);
    my $index = -1;
    my %hash;
    my ($found, $from, $to);

    $pattern =~ s/ /+/g;

    if ($type eq "current")
    {
	my $path = sprintf("/search/search.dll?MfcISAPICommand=GetResult&SortProperty=%s&ht=1&query=%s",
			    $item_search{'type'}, $pattern);

	if ($item_search{'_path'} ne $path)
	{
	    $item_search{'_path'} = $path;
	    delete $item_search{'_pos'};
	}
	else
	{
	    $item_search{'_pos'} += $skip;
	    delete $item_search{'_pos'} if $item_search{'_pos'} <= 0;
	}

	if (defined($item_search{'_pos'}))
	{
	    $path .= "&skip=" . $item_search{'_pos'};
	}
	
	$html = get("search.ebay.com", 80, $path);
    }
    else
    {
	my $path = sprintf("/cgi-bin/texis/ebaycomplete/results.html?dest=&cobrandpartner=&ht=1&maxRecordsPerPage=%d&query=%s&SortProperty=%s&SortOrder=%s",
			    50,
			    $pattern,
			    $completed_search{'type'},
			    "%5Ba%5D"); # [a] or [d]

	if ($completed_search{'path'} ne $pattern)
	{
	    $completed_search{'_path'} = $pattern;
	    delete $completed_search{'_pos'};
	}
	else
	{
	    $completed_search{'_pos'} += $skip;
	    delete $completed_search{'_pos'} if $completed_search{'_pos'} <= 0;
	}

	if (defined($completed_search{'_pos'}))
	{
	    $path .= "&skip=" . $completed_search{'_pos'};
	}

	$html = get("search-completed.ebay.com", 80, $path);
    }

    $labels{"${type}_status"}->set_text("");
    $clist->clear();

    if ($html =~ /(\d+)\s+(items\s+found\s+for.*?showing\s+items)\s+(\d+)\s+to\s+(\d+)\./is)
    {
	$found = $1;
	$from = $3;
	$to = $4;
		
	my $l = "$1 $2 $3 to $4";
	$l =~ s/<[^>]+>//g;
	$l =~ s/\n//g;
	$labels{"${type}_status"}->set_text($l);
    }

    while ($html =~ m,<td[^>]*>(.+?)</td>,igs)
    {
	$td = $1;
	if ($td =~ m,<a[^>]+>([^<]+)</a>,i)
	{
	    $anchor = $1;
	    next;
	}
	$td =~ s/<[^>]+>//g;
	$td =~ s/&nbsp;//g;
	$td =~ s/&pound;/\#/g;
	$td =~ s/\n//g;

	next if $td =~ /^$/; # checkbox
	next if $td =~ /bid now/i;

	if ($td =~ /^\s*(ends?|start time)\s*(pdt)?\s*$/i)
	{
	    $index = 0;
	    next;
	}

    	if ($td =~ /(\d+) items found for.*?items\s+(\d+)\s+to\s+(\d+)/is)
	{
	    $found = $1;
	    $from = $2;
	    $to = $3;
	    
	    $labels{"${type}_status"}->set_text($td);
	    next;
	}
	
	next if $index < 0;
	last if $td =~ /^item$/i;
	last if $index == 0 && $td =~ /^Note:/;

	$hash{$keys[$index++]} = $td;

	if ($index == $nkeys)
	{
	    $hash{title} = $anchor;
	    $clist->append($hash{item}, $hash{title}, $hash{price},
			   $hash{bids}, $hash{ends});

	    set_row_color($clist, $row, $hash{item}, $hash{price});

	    $row++;

	    $index = 0;
	    $anchor = "";
	    %hash = ();
	}
    }

    $buttons{"${type}_prev_page"}->hide;
    $buttons{"${type}_next_page"}->hide;

    if ($found > 50)
    {
	$buttons{"${type}_prev_page"}->show if $from > 50;
	$buttons{"${type}_next_page"}->show if $to < $found;
    }
}

sub load_file
{
    my ($file) = @_;

    undef $/;
    open(F, $file);
    my $s = <F>;
    close F;
    $/ = "\n";
    $s;
}

sub display_item
{
    my ($widget, $row, $column, $event) = @_;

    my $win = new Gtk::Window('dialog');
    my $item = $widget->get_text($row, 0);

    $win->set_title($item);
    $win->border_width(5);

    redisplay_item($win, $item);
}

sub redisplay_item
{
    my ($win, $item) = @_;
    my ($dir, $img);

    $dir = "$mebay_dir/$item";
    if (! -d $dir)
    {
	update_item($item);
    }

    my $box = new Gtk::VBox(0, 0);
    $box->show;

    my $html = load_file("$dir/item.html");
    $html =~ s/\n//g;
    $html =~ s/&nbsp;/ /g;
    $html =~ s,</*font.*?>,,g;

    my $font = load Gtk::Gdk::Font("fixed");
    my $info = new Gtk::Text(undef, undef);
    my %hash;
    if ($html =~ m,<title>(.+?)</title>,is)
    {
	my ($a, $b) = split(/ - /, $1, 2);
	$hash{'title'} = $b;
    }

    while ($html =~ m,<td[^>]*>(Started|Ends|Currently|First bid|Time left|Location|Country|Seller \(Rating\)|High bid|\# of bids)</td>\s*<td[^>]*>(.*?)</td>,igs)
    {
	my ($a, $b) = ($1, $2);
	$b =~ s/<[^>]+>//g;
	$hash{$a} = $b;
    }

    $hash{'# of bids'} =~ s/(\d+).*/$1/;

    $info->insert($font, $black_color, $white_color, <<"EOF");
     Seller: $hash{'Seller (Rating)'}
             $hash{'Location'}, $hash{'Country'}
    Started: $hash{'Started'}
       Ends: $hash{'Ends'}
  Time Left: $hash{'Time left'}

  First bid: $hash{'First bid'}
  # of bids: $hash{'# of bids'}
  Currently: $hash{'Currently'}
High bidder: $hash{'High bid'}
EOF

    my $l = new Gtk::Label("Item #$item - $hash{'title'}");
    $l->show;
    $box->pack_start($l, 1, 1, 0);

    $info->show;
    $box->pack_start($info, 1, 1, 0);

    $l = new Gtk::Label("Item Description:");
    $l->show;
    $box->pack_start($l, 1, 1, 0);

    my $ibox = new Gtk::HBox(0, 0);
    $ibox->show;
    $box->pack_start($ibox, 1, 1, 0);

    if (-f "$dir/item.img")
    {
	my $img = load_image Gtk::Gdk::ImlibImage("$dir/item.img");
	my $w = $img->rgb_width;
	my $h = $img->rgb_height;
	my $max = 300;

	if ($w > $h)
	{
	    $h /= $w / $max;
	    $w = $max;
	}
	else
	{
	    $w /= $h / $max;
	    $h = $max;
	}

	$img->render($w, $h);

	my $p = $img->move_image;
	my $m = $img->move_mask;

	my $pixmap = new Gtk::Pixmap($p, $m);
	$pixmap->show;
	$ibox->pack_start($pixmap, 1, 1, 0);
    }

    {
	my $desc = load_file("$dir/item.html");
	$desc =~ m,<blockquote[^>]*>(.+?)</blockquote>,is;
	$desc = $1;
	$desc =~ s/<br>\n/\n/ig;
	$desc =~ s/<br>/\n/ig;
	$desc =~ s/<p>/\n/ig;
	$desc =~ s/<[^>]+>//g;

	my $table = new Gtk::Table(2, 2, 0);
	$table->set_row_spacing(0, 2);
	$table->set_col_spacing(0, 2);
	$ibox->pack_start($table, 1, 1,0);
	$table->show;

	my $text = new Gtk::Text(undef, undef);
	$table->attach_defaults($text, 0, 1, 0, 1);
	$text->show;

	$text->insert(undef, $black_color, $white_color, $desc);

	my $hscrollbar = new Gtk::HScrollbar($text->hadj);
	$table->attach($hscrollbar, 0, 1,1,2,[-expand,-fill],[-fill],0,0);
	$hscrollbar->show;

	my $vscrollbar = new Gtk::VScrollbar($text->vadj);
	$table->attach($vscrollbar, 1, 2,0,1,[-fill],[-expand,-fill],0,0);
	$vscrollbar->show;
    }

    if (defined($purchased_db{$item}))
    {
	my $state = $purchased_db{$item};
	my $state_menu = new Gtk::OptionMenu;
	my $menu = new Gtk::Menu;
	my $mi;

	foreach my $i (0 .. $#purchased_states)
	{
	    $mi = new Gtk::MenuItem($purchased_states[$i]);
	    $mi->signal_connect("activate",
				sub { update_purchased_state($item, $i); });
	    $mi->show;
	    $menu->append($mi);

	    if ($state == $i)
	    {
		$menu->set_active($i);
	    }
	}

	$menu->show;
	$state_menu->set_menu($menu);
	$state_menu->show;

	my $hbox = new Gtk::HBox(0, 0);
	$hbox->show;
	$hbox->border_width(5);

	$l = new Gtk::Label("State of purchase: ");
	$l->show;

	$hbox->pack_start($l, 0, 0, 0);
	$hbox->pack_start($state_menu, 0, 0, 0);
	$box->pack_start($hbox, 0, 0, 0);
    }
    elsif (defined($sold_db{$item}))
    {
	my $state = $sold_db{$item};
	my $state_menu = new Gtk::OptionMenu;
	my $menu = new Gtk::Menu;
	my $mi;

	foreach my $i (0 .. $#sold_states)
	{
	    $mi = new Gtk::MenuItem($sold_states[$i]);
	    $mi->signal_connect("activate",
				sub { update_sold_state($item, $i); });
	    $mi->show;
	    $menu->append($mi);

	    if ($state == $i)
	    {
		$menu->set_active($i);
	    }
	}

	$menu->show;
	$state_menu->set_menu($menu);
	$state_menu->show;

	my $hbox = new Gtk::HBox(0, 0);
	$hbox->show;
	$hbox->border_width(5);

	$l = new Gtk::Label("State of sale: ");
	$l->show;

	$hbox->pack_start($l, 0, 0, 0);
	$hbox->pack_start($state_menu, 0, 0, 0);
	$box->pack_start($hbox, 0, 0, 0);
    }

    my $bbox = new Gtk::HBox(0, 0);
    $bbox->show;

    my $update = new Gtk::Button("Refresh");
    $update->signal_connect("clicked", sub { update_item($item); $win->remove($box); redisplay_item($win, $item); });
    $update->show;
    $bbox->pack_start($update, 1, 0, 0);

    my $notes = new Gtk::Button("Notes");
    $notes->signal_connect("clicked", sub { display_notes($item, $hash{'title'}); });
    $notes->show;
    $bbox->pack_start($notes, 1, 0, 0);

    my $watch;
    if (exists($mywatch_items{$item}))
    {
	$watch = new Gtk::Button("Cancel Watch");
	$watch->signal_connect("clicked", sub { nowatch($item); destroy $win; });
    } else
    {
	$watch = new Gtk::Button("Watch");
	$watch->signal_connect("clicked", sub { watch($item); });
    }
    $watch->show;
    $bbox->pack_start($watch, 1, 0, 0);

    my $close = new Gtk::Button("Close");
    $close->signal_connect("clicked", sub { destroy $win; });
    $close->show;
    $bbox->pack_start($close, 1, 0, 0);

    $box->pack_start($bbox, 0, 1, 5);

    $win->add($box);

    #my ($x, $y) = $root_win->get_pointer;
    #$win->set_uposition($x - $win->{width}, $y - $win->{height});
    #$close->set_uposition($x, $y);

    $win->show;
}

sub update_item
{
    my ($item) = @_;

    my $html = get("cgi.ebay.com", 80, "/aw-cgi/eBayISAPI.dll?ViewItem&item=$item");
    my $dir = "$mebay_dir/$item";
    mkdir($dir, 0700);

    open(F, ">$dir/item.html");
    print F $html;
    close F;

    $html =~ m,<hr><img src=\"([^\"]+)\"><p><a name=BID>,is;
    my $img = $1;
    if ($img =~ m,http://([^/:]+)(:\d+)?(/.*),)
    {
	my ($host, $port, $path) = ($1, $2, $3);
	$port = 80 unless $port;
	print "IMG host=$host port=$port path=$path\n" if $debug;
	get_image($host, $port, $path, "$dir/item.img");
    }
}

sub create_signin_window
{
    my ($callback) = @_;
    my $win = new Gtk::Window('dialog');
    $win->set_title("My eBay Sign In");
    $win->border_width(5);

    my $header = new Gtk::Label("My eBay Sign In");
    $header->show;

    my $vbox = new Gtk::VBox(0, 0);
    $vbox->show;
    $win->add($vbox);

    # left_attach, right_attach, top_attach, bottom_attach

    my $table = new Gtk::Table(2, 2, 0);
    $table->show;

    my $label = new Gtk::Label("User ID:");
    $label->show;
    $table->attach($label, 0, 1, 0, 1, {expand=>0,fill=>0}, {expand=>0,fill=>0}, 0, 0);

    my $userid = new Gtk::Entry;
    $userid->set_max_length(20);
    $userid->show;
    $table->attach($userid, 1, 2, 0, 1, {expand=>0,fill=>0}, {expand=>0,fill=>0}, 0, 0);

    $label = new Gtk::Label("Password:");
    $label->show;
    $table->attach($label, 0, 1, 1, 2, {expand=>0,fill=>0}, {expand=>0,fill=>0}, 0, 0);

    my $pass = new Gtk::Entry;
    $pass->set_max_length(20);
    $pass->set_visibility(0);
    $pass->show;
    $pass->signal_connect("activate", sub { $win->destroy; signin($userid->get_text(), $pass->get_text(), $callback); });
    $table->attach($pass, 1, 2, 1, 2, {expand=>0,fill=>0}, {expand=>0,fill=>0}, 0, 0);

    my $button = new Gtk::Button("Sign In");
    $button->signal_connect("clicked", sub { $win->destroy; signin($userid->get_text(), $pass->get_text(), $callback); });
    $button->show;

    my $cancel = new Gtk::Button("Cancel");
    $cancel->signal_connect("clicked", sub { $win->destroy; } );
    $cancel->show;

    my $bbox = new Gtk::HBox(0, 0);
    $bbox->show;
    $bbox->pack_start($button, 1, 0, 0);
    $bbox->pack_start($cancel, 1, 0, 0);

    $vbox->pack_start($header, 1, 1, 5);
    $vbox->pack_start($table, 0, 1, 5);
    $vbox->pack_start($bbox, 0, 1, 5);

    $win->show;
}

sub create_mybid_page
{
    my @titles = ('item#', 'item', 'start bid', 'curr bid', 'max bid', 'bids', 'timeleft', 'end');
    my @width = (80, 200, 50, 50, 50, 30, 70, 120);
    my @justification = ('left', 'left', 'right', 'right', 'right', 'right', 'right', 'right');
    my $window = new Gtk::ScrolledWindow(undef, undef);
    my $clist = new_with_titles Gtk::CList(@titles);
    my $header = new Gtk::Label("My eBay - Items I'm Bidding On");
    $header->show;

    $window->set_policy('automatic', 'automatic');
    $clist->set_row_height(20);

    for my $i (0 .. $#titles)
    {
	$clist->set_column_width($i, $width[$i]);
	$clist->set_column_justification($i, $justification[$i]);
    }

    $clist->set_usize(600, 200);
    $clist->set_selection_mode('single');
    $window->add($clist);

    $clist->show;
    $window->show;

    my $update = new Gtk::Button("Update");
    $update->signal_connect("clicked", sub { update_mybid($clist); });
    $update->show;

    my $hbox = new Gtk::HBox(0, 0);
    $hbox->show;
    $hbox->pack_start($update, 1, 0, 0);

    my $box = new Gtk::VBox(0, 0);
    $box->pack_start($header, 0, 1, 5);
    $box->pack_start($window, 1, 1, 0);
    $box->pack_start($hbox, 0, 0, 5);
    $box->show;

    ($clist, $box);
}

sub create_mywatch_page
{
    my @titles = ('item#', 'item', 'curr bid', 'bids', 'timeleft');
    my @width = (80, 300, 50, 30, 80);
    my @justification = ('left', 'left', 'right', 'right', 'right');
    my $window = new Gtk::ScrolledWindow(undef, undef);
    my $clist = new_with_titles Gtk::CList(@titles);
    my $header = new Gtk::Label("My eBay - Items I'm Watching");
    $header->show;

    $window->set_policy('automatic', 'automatic');
    $clist->set_row_height(20);

    for my $i (0 .. $#titles)
    {
	$clist->set_column_width($i, $width[$i]);
	$clist->set_column_justification($i, $justification[$i]);
    }

    $clist->set_usize(600, 200);
    $clist->set_selection_mode('single');
    $window->add($clist);

    $clist->show;
    $window->show;

    my $update = new Gtk::Button("Update");
    $update->signal_connect("clicked", sub { update_mywatch($clist); });
    $update->show;

    my $hbox = new Gtk::HBox(0, 0);
    $hbox->show;
    $hbox->pack_start($update, 1, 0, 0);

    my $box = new Gtk::VBox(0, 0);
    $box->pack_start($header, 0, 1, 5);
    $box->pack_start($window, 1, 1, 0);
    $box->pack_start($hbox, 0, 0, 5);
    $box->show;

    ($clist, $box);
}

sub create_search_page
{
    my @titles = ('item#', 'item', 'price', 'bids', 'time');
    my @width = (80, 300, 60, 30, 80);
    my @justification = ('left', 'left', 'right', 'right', 'right');
    my $window = new Gtk::ScrolledWindow(undef, undef);
    my $clist = new_with_titles Gtk::CList(@titles);
    my $header = new Gtk::Label("Search");
    $header->show;

    $window->set_policy('automatic', 'automatic');
    $clist->set_row_height(20);

    for my $i (0 .. $#titles)
    {
	$clist->set_column_width($i, $width[$i]);
	$clist->set_column_justification($i, $justification[$i]);
    }

    $clist->set_usize(600, 200);
    $clist->set_selection_mode('single');

    my $vbox = new Gtk::VBox(0, 0);
    $vbox->show;

    my $hbox = new Gtk::HBox(0, 0);
    my $label = new Gtk::Label("Search:");
    $label->show;
    my $entry = new Gtk::Entry;
    $entry->set_max_length(50);
    $entry->show;

    my $sortmenu = new Gtk::OptionMenu;
    my $menu = new Gtk::Menu;
    my @types = ("Items ending first", "Newly-listed items first",
		 "Lowest prices first", "Highest prices first");
    my @values = qw(MetaEndSort MetaNewSort
		    MetaLowestPriceSort MetaHighestPriceSort);
    foreach my $i (0 .. $#types)
    {
	my $mi = new Gtk::MenuItem($types[$i]);
	$mi->signal_connect("activate", sub { $item_search{'type'} = $values[$i]; });
	$mi->show;
	$menu->append($mi);
    }
    $menu->show;
    $sortmenu->set_menu($menu);
    $sortmenu->show;
    $item_search{'type'} = $values[0];

    $entry->signal_connect("activate", sub { update_search($clist, "current", $entry->get_text()); });

    my $prev_page = new Gtk::Button("Previous Page");
    $prev_page->signal_connect("clicked", sub { update_search($clist, "current", $entry->get_text(), -50); });
    my $next_page = new Gtk::Button("Next Page");
    $next_page->signal_connect("clicked", sub { update_search($clist, "current", $entry->get_text(), 50); });
    $buttons{'current_prev_page'} = $prev_page;
    $buttons{'current_next_page'} = $next_page;

    $hbox->pack_start($label, 0, 0, 0);
    $hbox->pack_start($entry, 1, 1, 0);
    $hbox->pack_start($sortmenu, 0, 0, 0);
    $hbox->show;

    $window->add($clist);

    my $search = new Gtk::Button("Search");
    $search->signal_connect("clicked", sub { update_search($clist, "current", $entry->get_text()); });
    $search->show;

    my $bbox = new Gtk::HBox(0, 0);
    $bbox->show;
    $bbox->pack_start($search, 1, 0, 0);
    $bbox->pack_start($prev_page, 0, 0, 2);
    $bbox->pack_start($next_page, 0, 0, 2);

    $vbox->pack_start($header, 0, 1, 5);
    $vbox->pack_start($window, 1, 1, 0);
    $vbox->pack_start($hbox, 0, 1, 0);
    $vbox->pack_start($bbox, 0, 1, 5);

    $labels{'current_status'} = new Gtk::Label("");
    $labels{'current_status'}->show;
    $vbox->pack_start($labels{'current_status'}, 0, 1, 1);

    $clist->show;
    $window->show;

    ($clist, $vbox);
}

sub create_completed_page
{
    my @titles = ('item#', 'item', 'price', 'bids', 'time');
    my @width = (80, 300, 60, 30, 80);
    my @justification = ('left', 'left', 'right', 'right', 'right');
    my $window = new Gtk::ScrolledWindow(undef, undef);
    my $clist = new_with_titles Gtk::CList(@titles);
    my $header = new Gtk::Label("Search Completed Items");
    $header->show;

    $window->set_policy('automatic', 'automatic');
    $clist->set_row_height(20);

    for my $i (0 .. $#titles)
    {
	$clist->set_column_width($i, $width[$i]);
	$clist->set_column_justification($i, $justification[$i]);
    }

    $clist->set_usize(600, 200);
    $clist->set_selection_mode('single');

    my $vbox = new Gtk::VBox(0, 0);
    $vbox->show;

    my $hbox = new Gtk::HBox(0, 0);
    my $label = new Gtk::Label("Search:");
    $label->show;
    my $entry = new Gtk::Entry;
    $entry->set_max_length(50);
    $entry->show;

    my $sortmenu = new Gtk::OptionMenu;
    my $menu = new Gtk::Menu;
    my @types = ("Ending Date", "Starting Date",
		 "Bid Price", "Search Ranking");
    my @values = qw(MetaEndSort MetaStartSort
		    MetaCurrentPriceSort Ranking);
    foreach my $i (0 .. $#types)
    {
	my $mi = new Gtk::MenuItem($types[$i]);
	$mi->signal_connect("activate", sub { $completed_search{'type'} = $values[$i]; });
	$mi->show;
	$menu->append($mi);
    }
    $menu->show;
    $sortmenu->set_menu($menu);
    $sortmenu->show;
    $completed_search{'type'} = $values[0];

    $entry->signal_connect("activate", sub { update_search($clist, "completed", $entry->get_text()); });

    my $prev_page = new Gtk::Button("Previous Page");
    $prev_page->signal_connect("clicked", sub { update_search($clist, "completed", $entry->get_text(), -50); });
    my $next_page = new Gtk::Button("Next Page");
    $next_page->signal_connect("clicked", sub { update_search($clist, "completed", $entry->get_text(), 50); });
    $buttons{'completed_prev_page'} = $prev_page;
    $buttons{'completed_next_page'} = $next_page;

    $hbox->pack_start($label, 0, 0, 0);
    $hbox->pack_start($entry, 1, 1, 0);
    $hbox->pack_start($sortmenu, 0, 0, 0);
    $hbox->show;

    $window->add($clist);

    my $search = new Gtk::Button("Search");
    $search->signal_connect("clicked", sub { update_search($clist, "completed", $entry->get_text()); });
    $search->show;

    my $bbox = new Gtk::HBox(0, 0);
    $bbox->show;
    $bbox->pack_start($search, 1, 0, 0);
    $bbox->pack_start($prev_page, 0, 0, 2);
    $bbox->pack_start($next_page, 0, 0, 2);

    $vbox->pack_start($header, 0, 1, 5);
    $vbox->pack_start($window, 1, 1, 0);
    $vbox->pack_start($hbox, 0, 1, 0);
    $vbox->pack_start($bbox, 0, 1, 5);

    $labels{'completed_status'} = new Gtk::Label("");
    $labels{'completed_status'}->show;
    $vbox->pack_start($labels{'completed_status'}, 0, 1, 1);

    $clist->show;
    $window->show;

    ($clist, $vbox);
}

sub create_bidder_page
{
    my @titles = ('item#', 'start', 'end', 'price', 'title', 'high bidder');
    my @width = (80, 80, 120, 60, 300, 100);
    my @justification = ('left', 'left', 'left', 'right', 'left', 'left');
    my $window = new Gtk::ScrolledWindow(undef, undef);
    my $clist = new_with_titles Gtk::CList(@titles);
    my $header = new Gtk::Label("Find items by Bidder");
    $header->show;

    $window->set_policy('automatic', 'automatic');
    $clist->set_row_height(20);

    for my $i (0 .. $#titles)
    {
	$clist->set_column_width($i, $width[$i]);
	$clist->set_column_justification($i, $justification[$i]);
    }

    $clist->set_usize(600, 200);
    $clist->set_selection_mode('single');

    my $vbox = new Gtk::VBox(0, 0);
    $vbox->show;

    $window->add($clist);

    my $hbox = new Gtk::HBox(0, 0);
    my $label = new Gtk::Label("User ID:");
    $label->show;
    my $entry = new Gtk::Entry;
    $entry->set_max_length(50);
    $entry->show;

    my $sortmenu = new Gtk::OptionMenu;
    my $menu = new Gtk::Menu;
    my $mi;
    my @list = ("Item #", "Start", "End", "Price", "Title", "High Bidder");
    foreach my $i (0 .. $#list)
    {
	$mi = new Gtk::MenuItem("Sort by " . $list[$i]);
	$mi->signal_connect("activate", sub { $bidder_search{'sort'} = $i+1; });
	$mi->show;
	$menu->append($mi);
    }
    $menu->show;
    $sortmenu->set_menu($menu);
    $sortmenu->show;
    $bidder_search{'sort'} = 1;

    my $completed_menu = new Gtk::OptionMenu;
    $menu = new Gtk::Menu;
    $mi = new Gtk::MenuItem("Current Auctions");
    $mi->signal_connect("activate", sub { $bidder_search{'completed'} = 0; });
    $mi->show;
    $menu->append($mi);
    $mi = new Gtk::MenuItem("Include Completed Auctions");
    $mi->signal_connect("activate", sub { $bidder_search{'completed'} = 1; });
    $mi->show;
    $menu->append($mi);
    $menu->show;
    $completed_menu->set_menu($menu);
    $completed_menu->show;
    $bidder_search{'completed'} = 0;

    my $all_menu = new Gtk::OptionMenu;
    $menu = new Gtk::Menu;
    $mi = new Gtk::MenuItem("With any bids");
    $mi->signal_connect("activate", sub { $bidder_search{'all'} = 1; });
    $mi->show;
    $menu->append($mi);
    $mi = new Gtk::MenuItem("Only high bidder");
    $mi->signal_connect("activate", sub { $bidder_search{'all'} = 0; });
    $mi->show;
    $menu->append($mi);
    $menu->show;
    $all_menu->set_menu($menu);
    $all_menu->show;
    $bidder_search{'all'} = 1;

    $entry->signal_connect("activate", sub { update_listing($clist, "bids", $entry->get_text()); });

    $hbox->pack_start($label, 0, 0, 0);
    $hbox->pack_start($entry, 1, 1, 0);
    $hbox->pack_start($sortmenu, 0, 0, 0);
    $hbox->pack_start($completed_menu, 0, 0, 0);
    $hbox->pack_start($all_menu, 0, 0, 0);

    $hbox->show;

    my $search = new Gtk::Button("Search");
    $search->signal_connect("clicked", sub { update_listing($clist, "bids", $entry->get_text()); });
    $search->show;

    my $bbox = new Gtk::HBox(0, 0);
    $bbox->show;
    $bbox->pack_start($search, 1, 0, 0);

    $vbox->pack_start($header, 0, 1, 5);
    $vbox->pack_start($window, 1, 1, 0);
    $vbox->pack_start($hbox, 0, 1, 0);
    $vbox->pack_start($bbox, 0, 1, 5);

    $labels{'bids_status'} = new Gtk::Label("");
    $labels{'bids_status'}->show;
    $vbox->pack_start($labels{'bids_status'}, 0, 1, 1);

    $clist->show;
    $window->show;

    ($clist, $vbox);
}

sub create_seller_page
{
    my @titles = ('item#', 'start', 'end', 'price', 'title', 'high bidder');
    my @width = (80, 80, 120, 60, 300, 100);
    my @justification = ('left', 'left', 'left', 'right', 'left', 'left');
    my $window = new Gtk::ScrolledWindow(undef, undef);
    my $clist = new_with_titles Gtk::CList(@titles);
    my $header = new Gtk::Label("Find items by Seller");
    $header->show;

    $window->set_policy('automatic', 'automatic');
    $clist->set_row_height(20);

    for my $i (0 .. $#titles)
    {
	$clist->set_column_width($i, $width[$i]);
	$clist->set_column_justification($i, $justification[$i]);
    }

    $clist->set_usize(600, 200);
    $clist->set_selection_mode('single');

    my $vbox = new Gtk::VBox(0, 0);
    $vbox->show;

    $window->add($clist);

    my $hbox = new Gtk::HBox(0, 0);
    my $label = new Gtk::Label("Seller's User ID:");
    $label->show;
    my $entry = new Gtk::Entry;
    $entry->set_max_length(50);
    $entry->show;

    my $sortmenu = new Gtk::OptionMenu;
    my $mi;
    my $menu = new Gtk::Menu;
    my @list = ("Item #", "Start", "End", "Price", "Title", "High Bidder");
    foreach my $i (0 .. $#list)
    {
	my $mi = new Gtk::MenuItem("Sort by " . $list[$i]);
	$mi->signal_connect("activate", sub { $seller_search{'sort'} = $i+1; });
	$mi->show;
	$menu->append($mi);
    }
    $menu->show;
    $sortmenu->set_menu($menu);
    $sortmenu->show;
    $seller_search{'sort'} = 1;

    my $since_menu = new Gtk::OptionMenu;
    $menu = new Gtk::Menu;
    @list = ("Current Auctions", "Completed Last day",
	     "Completed Last 2 days", "Completed Last week",
	     "Completed Last 2 weeks", "Completed Last 4 weeks",
	     "All");
    my @since = (-1, 1, 2, 7, 14, 28, 30);
    foreach my $i (0 .. $#list)
    {
	$mi = new Gtk::MenuItem("Include " . $list[$i]);
	$mi->signal_connect("activate", sub { $seller_search{'since'} = $since[$i]; });
	$mi->show;
	$menu->append($mi);
    }
    $menu->show;
    $since_menu->set_menu($menu);
    $since_menu->show;
    $seller_search{'since'} = -1;

    $entry->signal_connect("activate", sub { update_listing($clist, "auctions", $entry->get_text()); });

    $hbox->pack_start($label, 0, 0, 0);
    $hbox->pack_start($entry, 1, 1, 0);
    $hbox->pack_start($sortmenu, 0, 0, 0);
    $hbox->pack_start($since_menu, 0, 0, 0);
    $hbox->show;

    my $search = new Gtk::Button("Search");
    $search->signal_connect("clicked", sub { update_listing($clist, "auctions", $entry->get_text()); });
    $search->show;

    my $bbox = new Gtk::HBox(0, 0);
    $bbox->show;
    $bbox->pack_start($search, 1, 0, 0);

    $vbox->pack_start($header, 0, 1, 5);
    $vbox->pack_start($window, 1, 1, 0);
    $vbox->pack_start($hbox, 0, 1, 0);
    $vbox->pack_start($bbox, 0, 1, 5);

    $labels{'auctions_status'} = new Gtk::Label("");
    $labels{'auctions_status'}->show;
    $vbox->pack_start($labels{'auctions_status'}, 0, 1, 1);

    $clist->show;
    $window->show;

    ($clist, $vbox);
}

sub update_listing
{
    my ($clist, $type, $pattern) = @_;
    my @keys = qw(item start end price title highbidder);
    my $nkeys = scalar(@keys);
    my ($html, $td, $anchor, $row);
    my $index = -1;
    my %hash;

    $pattern =~ s/ /+/g;

    my $path;
    if ($type eq "bids")
    {
	$path = sprintf("/aw-cgi/eBayISAPI.dll?ViewBidItems&userid=%s&completed=%d&sort=%d&all=%s&page=1&rows=%d",
			$pattern,
			$bidder_search{'completed'},
			$bidder_search{'sort'},
			$bidder_search{'all'},
			0);
    }
    elsif ($type eq "purchased")
    {
	$path = sprintf("/aw-cgi/eBayISAPI.dll?ViewBidItems&userid=%s&completed=%d&sort=%d&all=%s&page=1&rows=%d",
			$pattern,
			1, # inlcude completed
			3, # sort by end
			0, # only high bidder
			0);
    }
    elsif ($type eq "sold")
    {
	$path = sprintf("/aw-cgi/eBayISAPI.dll?ViewListedItems&userid=%s&include=0&since=%d&sort=%d&rows=%d",
			$pattern,
			30, # last 30 days
			3,  # sort by end
			0);
    }
    elsif ($type eq "auctions")
    {
	$path = sprintf("/aw-cgi/eBayISAPI.dll?ViewListedItems&userid=%s&include=0&since=%d&sort=%d&rows=%d",
			$pattern,
			$seller_search{'since'},
			$seller_search{'sort'},
			0);
    }

    $labels{"${type}_status"}->set_text("");

    $html = get("cgi3.ebay.com", 80, $path);
    $clist->clear();

    while ($html =~ m,<t[dh][^>]*>(.+?)</t[dh]>,igs)
    {
	$td = $1;
	if ($td =~ m,<a[^>]+>([^<]+)</a>,i)
	{
	    $anchor = $1;
	    $td = $anchor;
	}
	elsif ($td =~ m,high bidder,i)
	{
	    $index = 0;
	    next;
	}

	$td =~ s/<[^>]+>//g;
	$td =~ s/&nbsp;//g;
	$td =~ s/&pound;/\#/g;

	if ($td =~ /\d+ items found for/)
	{
	    $labels{"${type}_status"}->set_text($td);
	    next;
	}

	next if $index < 0;
	#last if $td =~ /^item$/i;

	$hash{$keys[$index++]} = $td;

	if ($index == $nkeys)
	{
	    if ($type eq "purchased")
	    {
		my $state = 0;
		if (defined($purchased_db{$hash{item}}))
		{
		    $state = $purchased_db{$hash{item}};
		}
		else
		{
		    $purchased_db{$hash{item}} = $state;
		}

		$clist->append($hash{item}, $hash{end}, $hash{price}, $hash{title},
			       $purchased_states[$state]);
	    }
	    elsif ($type eq "sold")
	    {
		my $state = 0;
		if (defined($sold_db{$hash{item}}))
		{
		    $state = $sold_db{$hash{item}};
		}
		else
		{
		    $sold_db{$hash{item}} = $state;
		}

		$clist->append($hash{item}, $hash{end}, $hash{price}, $hash{title},
			       $hash{highbidder}, $sold_states[$state]);
	    }
	    else
	    {
		$clist->append($hash{item}, $hash{start}, $hash{end},
			       $hash{price}, $hash{title}, $hash{highbidder});
		set_row_color($clist, $row, $hash{item}, $hash{price});
	    }

	    $row++;

	    $index = 0;
	    $anchor = "";
	    %hash = ();
	}
    }
}

sub update_feedback
{
    my ($text, $userid) = @_;
    my $font = load Gtk::Gdk::Font("fixed");
    my $html = get("cgi1.ebay.com", 80, "/aw-cgi/eBayISAPI.dll?ViewFeedback&userid=" . $userid);
    my @summary;
    my $context;
    my $td;

    $text->set_point(0);
    $text->forward_delete($text->get_length());

    while ($html =~ m,<td[^>]*>(.+?)</td>,igs)
    {
	$td = $1;

	if ($td =~ m,<a[^>]+>([^<]+)</a>,i)
	{
	    $td = $1;
	}
	$td =~ s/<[^>]+>//g;
	$td =~ s/&nbsp;//g;
	$td =~ s/\n/ /g;
	$td =~ s/^\s+//g;
	$td =~ s/\s+$//g;

	if ($td =~ /(positive|neutral|negative|total|bid retractions)/i)
	{
	    $context = "summary";
	}
	elsif ($td =~ /^Auctions/i)
	{
	    $text->insert($font, undef, undef,
			  sprintf("              7 days  Month  6 Months\n"));
	    $text->insert($font, undef, undef,
			  sprintf("    Positive    %3d    %3d     %3d\n", $summary[0], $summary[1], $summary[2]));
	    $text->insert($font, undef, undef,
			  sprintf("     Neutral    %3d    %3d     %3d\n", $summary[3], $summary[4], $summary[5]));
	    $text->insert($font, undef, undef,
			  sprintf("    Negative    %3d    %3d     %3d\n", $summary[6], $summary[7], $summary[8]));
	    $text->insert($font, undef, undef,
			  sprintf("       Total    %3d    %3d     %3d\n", $summary[9], $summary[10], $summary[11]));
	    $text->insert($font, undef, undef, "\n");
	    $text->insert($font, undef, undef,
			  sprintf("Bid Retract.    %3d    %3d     %3d\n", $summary[12], $summary[13], $summary[14]));

	    $context = "auctions";
	}
	elsif ($context eq "summary")
	{
	    push(@summary, $td);
	}
	elsif ($context eq "auctions")
	{
	    $text->insert($font, undef, undef, $td);
	}
    }

    $text->insert($font, undef, undef, "\n");
}

sub create_feedback_page
{
    my $vbox = new Gtk::VBox(0, 0);
    $vbox->show;

    my $header = new Gtk::Label("View Feedback");
    $header->show;

    my $table = new Gtk::Table(2, 2, 0);
    $table->set_row_spacing(0, 2);
    $table->set_col_spacing(0, 2);
    $table->show;

    my $text = new Gtk::Text(undef, undef);
    $table->attach_defaults($text, 0, 1, 0, 1);
    $text->show;

    my $hscrollbar = new Gtk::HScrollbar($text->hadj);
    $table->attach($hscrollbar, 0, 1,1,2,[-expand,-fill],[-fill],0,0);
    $hscrollbar->show;

    my $vscrollbar = new Gtk::VScrollbar($text->vadj);
    $table->attach($vscrollbar, 1, 2,0,1,[-fill],[-expand,-fill],0,0);
    $vscrollbar->show;

    my $hbox = new Gtk::HBox(0, 0);

    my $label = new Gtk::Label("User ID:");
    $label->show;

    my $entry = new Gtk::Entry;
    $entry->set_max_length(50);
    $entry->signal_connect("activate", sub { update_feedback($text, $entry->get_text()); });
    $entry->show;

    my $view = new Gtk::Button("View");
    $view->signal_connect("clicked", sub { update_feedback($text, $entry->get_text()); });
    $view->show;

    $hbox->pack_start($label, 0, 0, 5);
    $hbox->pack_start($entry, 0, 0, 5);
    $hbox->pack_start($view, 0, 0, 5);
    $hbox->show;

    $vbox->pack_start($header, 0, 1, 5);
    $vbox->pack_start($table, 0, 1, 5);
    $vbox->pack_start($hbox, 0, 1, 5);

    $vbox;
}

sub create_about_page
{
    my $vbox = new Gtk::VBox(0, 0);
    $vbox->show;

    my $font = load Gtk::Gdk::Font("fixed");
    my $text = new Gtk::Text(undef, undef);
    $text->insert($font, $black_color, $white_color, copyleft());
    $text->show;
    $vbox->pack_start($text, 1, 1, 5);
    $vbox;
}

sub create_purchased_page
{
    my @titles = ('item#', 'end', 'price', 'title', 'state');
    my @width = (80, 120, 60, 300, 100);
    my @justification = ('left', 'left', 'right', 'left', 'left');
    my $window = new Gtk::ScrolledWindow(undef, undef);
    my $clist = new_with_titles Gtk::CList(@titles);
    my $header = new Gtk::Label("Items Purchased");
    $header->show;

    $window->set_policy('automatic', 'automatic');
    $clist->set_row_height(20);

    for my $i (0 .. $#titles)
    {
	$clist->set_column_width($i, $width[$i]);
	$clist->set_column_justification($i, $justification[$i]);
    }

    $clist->set_usize(600, 200);
    $clist->set_selection_mode('single');

    my $vbox = new Gtk::VBox(0, 0);
    $vbox->show;

    $window->add($clist);

    my $hbox = new Gtk::HBox(0, 0);
    my $label = new Gtk::Label("User ID:");
    $label->show;
    my $entry = new Gtk::Entry;
    $entry->set_max_length(50);
    $entry->show;

    $entry->signal_connect("activate", sub { update_listing($clist, "purchased", $entry->get_text()); });

    $hbox->pack_start($label, 0, 0, 0);
    $hbox->pack_start($entry, 1, 1, 0);

    $hbox->show;

    my $update = new Gtk::Button("Update");
    $update->signal_connect("clicked", sub { update_listing($clist, "purchased", $entry->get_text()); });
    $update->show;

    my $bbox = new Gtk::HBox(0, 0);
    $bbox->show;
    $bbox->pack_start($update, 1, 0, 0);

    $vbox->pack_start($header, 0, 1, 5);
    $vbox->pack_start($window, 1, 1, 0);
    $vbox->pack_start($hbox, 0, 1, 0);
    $vbox->pack_start($bbox, 0, 1, 5);

    $labels{'purchased_status'} = new Gtk::Label("");
    $labels{'purchased_status'}->show;
    $vbox->pack_start($labels{'purchased_status'}, 0, 1, 1);

    $clist->show;
    $window->show;

    ($clist, $vbox);
}

sub update_purchased_state
{
    my ($item, $state) = @_;

    $purchased_db{$item} = $state;
    $purchased_x->sync;

    my $row = find_clist_item($purchased_clist, $item);
    if ($row != -1)
    {
	$purchased_clist->set_text($row, 4, $purchased_states[$state]);
    }
}

sub create_sold_page
{
    my @titles = ('item#', 'end', 'price', 'title', 'high bidder', 'state');
    my @width = (80, 120, 60, 200, 100, 100);
    my @justification = ('left', 'left', 'right', 'left', 'left', 'left');
    my $window = new Gtk::ScrolledWindow(undef, undef);
    my $clist = new_with_titles Gtk::CList(@titles);
    my $header = new Gtk::Label("Items Sold");
    $header->show;

    $window->set_policy('automatic', 'automatic');
    $clist->set_row_height(20);

    for my $i (0 .. $#titles)
    {
	$clist->set_column_width($i, $width[$i]);
	$clist->set_column_justification($i, $justification[$i]);
    }

    $clist->set_usize(600, 200);
    $clist->set_selection_mode('single');

    my $vbox = new Gtk::VBox(0, 0);
    $vbox->show;

    $window->add($clist);

    my $hbox = new Gtk::HBox(0, 0);
    my $label = new Gtk::Label("User ID:");
    $label->show;
    my $entry = new Gtk::Entry;
    $entry->set_max_length(50);
    $entry->show;

    $entry->signal_connect("activate", sub { update_listing($clist, "sold", $entry->get_text()); });

    $hbox->pack_start($label, 0, 0, 0);
    $hbox->pack_start($entry, 1, 1, 0);

    $hbox->show;

    my $update = new Gtk::Button("Update");
    $update->signal_connect("clicked", sub { update_listing($clist, "sold", $entry->get_text()); });
    $update->show;

    my $bbox = new Gtk::HBox(0, 0);
    $bbox->show;
    $bbox->pack_start($update, 1, 0, 0);

    $vbox->pack_start($header, 0, 1, 5);
    $vbox->pack_start($window, 1, 1, 0);
    $vbox->pack_start($hbox, 0, 1, 0);
    $vbox->pack_start($bbox, 0, 1, 5);

    $labels{'sold_status'} = new Gtk::Label("");
    $labels{'sold_status'}->show;
    $vbox->pack_start($labels{'sold_status'}, 0, 1, 1);

    $clist->show;
    $window->show;

    ($clist, $vbox);
}

sub update_sold_state
{
    my ($item, $state) = @_;

    $sold_db{$item} = $state;
    $sold_x->sync;
}

sub display_notes
{
    my ($item, $title) = @_;

    my $win = new Gtk::Window('dialog');
    $win->set_title("Notes: #$item - $title");
    $win->border_width(5);

    my $box = new Gtk::VBox(0, 0);
    $box->show;

    my $l = new Gtk::Label("Notes: #$item - $title");
    $l->show;
    $box->pack_start($l, 1, 1, 0);

    my $table = new Gtk::Table(2, 2, 0);
    $table->set_row_spacing(0, 2);
    $table->set_col_spacing(0, 2);
    $box->pack_start($table, 1, 1,0);
    $table->show;

    my $text = new Gtk::Text(undef, undef);
    $table->attach_defaults($text, 0, 1, 0, 1);
    $text->insert(undef, $black_color, $white_color, $notes_db{$item});
    $text->set_editable(1);
    $text->show;

    my $hscrollbar = new Gtk::HScrollbar($text->hadj);
    $table->attach($hscrollbar, 0, 1,1,2,[-expand,-fill],[-fill],0,0);
    $hscrollbar->show;

    my $vscrollbar = new Gtk::VScrollbar($text->vadj);
    $table->attach($vscrollbar, 1, 2,0,1,[-fill],[-expand,-fill],0,0);
    $vscrollbar->show;

    my $bbox = new Gtk::HBox(0, 0);
    $bbox->show;

    my $save = new Gtk::Button("Save");
    $save->signal_connect("clicked", sub { update_notes($item, $text->get_chars(0, -1)); });
    $save->show;
    $bbox->pack_start($save, 1, 0, 0);

    my $delete = new Gtk::Button("Delete");
    $delete->signal_connect("clicked",
			    sub { update_notes($item, undef);
				  $text->set_point(0);
				  $text->forward_delete($text->get_length()); });
    $delete->show;
    $bbox->pack_start($delete, 1, 0, 0);

    my $close = new Gtk::Button("Close");
    $close->signal_connect("clicked", sub { destroy $win; });
    $close->show;
    $bbox->pack_start($close, 1, 0, 0);

    $box->pack_start($bbox, 0, 1, 5);

    $win->add($box);
    $win->show;
}

sub update_notes
{
    my ($item, $notes) = @_;

    if (!defined($notes))
    {
	delete $notes_db{$item};
    }
    else
    {
	$notes_db{$item} = $notes;
    }
    $notes_x->sync;
}

sub find_clist_item
{
    my ($clist, $item) = @_;

    for (my $i = 0; $i < $clist->rows; $i++)
    {
        return $i if $clist->get_text($i, 0) eq $item;
    }

    -1;
}


# sub create_prefs_page
# {
#     my ($label, $entry, $table, $hbox);

#     my $vbox = new Gtk::VBox(0, 0);
#     $vbox->border_width(10);
#     $vbox->show;

#     $label = new Gtk::Label("MeBay Preferences");
#     $label->show;
#     $vbox->pack_start($label, 0, 1, 5);

#     $hbox = new Gtk::HBox(0, 0);
#     $hbox->show;
#     $label = new Gtk::Label("User ID:");
#     $label->show;
#     $hbox->pack_start($label, 0, 1, 5);
#     $entry = new Gtk::Entry();
#     $entry->show;
#     $hbox->pack_start($entry, 0, 1, 5);
#     $vbox->pack_start($hbox, 0, 1, 5);

#     $vbox;
# }

sub post
{
    my ($host, $port, $path, $ref) = @_;
    my %data = %$ref;
    my $content;

    # this needs to be first
    if (exists($data{'MfcISAPICommand'}))
    {
	$content = "MfcISAPICommand=" . $data{'MfcISAPICommand'};
	delete $data{'MfcISAPICommand'};
    }

    foreach (keys %data)
    {
	$content .= "&" if $content;
	$content .= $_ . "=" . $data{$_};
    }
    my $content_length = length($content);

    my $sock;
    if (defined($http_proxy_host) && defined($http_proxy_port))
    {
	$sock = xconnect($http_proxy_host, $http_proxy_port);
	print $sock "POST http://$host:$port$path HTTP/1.0\n";
    }
    else
    {
	$sock = xconnect($host, $port);
	print $sock "POST $path HTTP/1.0\n";
    }
    if ($ebay{'cookie'} and $host =~ /ebay.com$/i)
    {
	print $sock "Cookie: " . $ebay{'cookie'} . "\n";
    }
    print $sock "User-agent: $user_agent\n";
    print $sock "Content-type: application/x-www-form-urlencoded\n";
    print $sock "Content-length: $content_length\n";
    print $sock "\n$content\n";

    my $html;
    while (<$sock>)
    {
	$html .= $_;
    }
    close $sock;

    if ($html =~ /Location:\s+([^\n]+)/i)
    {
	my $location = $1;
	if ($location =~ m,http://([^/:]+)(:\d+)?(/.*),)
	{
	    my ($host, $port, $path) = ($1, $2, $3);
	    $port =~ s/://;
	    $port = 80 unless $port;
	    $html = get($host, $port, $path);
	}
    }

    $html;
}

sub get
{
    my ($host, $port, $path) = @_;
    my $html;

    my $sock;
    if (defined($http_proxy_host) && defined($http_proxy_port))
    {
	$sock = xconnect($http_proxy_host, $http_proxy_port);
	print $sock "GET http://$host:$port$path HTTP/1.0\n";
    }
    else
    {
	$sock = xconnect($host, $port);
	print $sock "GET $path HTTP/1.0\n";
    }
    
    print $sock "User-Agent: $user_agent\n";
    if ($ebay{'cookie'} and $host =~ /ebay.com$/i)
    {
	print $sock "Cookie: " . $ebay{'cookie'} . "\n";
    }
    print $sock "\n";
    while (<$sock>)
    {
	s/\&\#(\d+)\;/chr($1)/eg;
	$html .= $_;
    }
    close $sock;

    if ($html =~ /Location:\s+([^\n]+)/i)
    {
	my $location = $1;
	if ($location =~ m,http://([^/:]+)(:\d+)?(/.*),)
	{
	    my ($host, $port, $path) = ($1, $2, $3);
	    $port = 80 unless $port;
	    $html = get($host, $port, $path);
	}
    }

    $html;
}

sub get_image
{
    my($host, $port, $path, $out) = @_;

    my $sock;
    if (defined($http_proxy_host) && defined($http_proxy_port))
    {
	$sock = xconnect($http_proxy_host, $http_proxy_port);
	print $sock "GET http://$host:$port$path HTTP/1.0\n";
    }
    else
    {
	$sock = xconnect($host, $port);
	print $sock "GET $path HTTP/1.0\n";
    }

    print $sock "User-Agent: $user_agent\n";
    if ($ebay{'cookie'} && $host =~ /ebay.com$/i)
    {
	print $sock "Cookie: " . $ebay{'cookie'} . "\n";
    }
    print $sock "\n";
    my $data = "";
    my $len = 0;
    my $br = 0;
    while ($br = $sock->read($data, 8192, $len))
    {
	$len += $br;
    }
    disconnect($sock);

    my ($headers, $content) = split(/\r?\n\r?\n/, $data, 2);
    if ($headers =~ /image\/(gif|jpe?g)/)
    {
        open(OUT, ">$out") or die "$out $!";
        print OUT $content;
        close OUT;
    }
    elsif ($headers =~ /text\/html/)
    {
	return $content;
    }
}

sub xconnect
{
    my ($that_host, $that_port) = @_;
    my ($pat, $name, $aliases, $proto, $port, $udp);
    my (@bytes, $addrtype, $length, $old);
    my ($that, $that_addr, $that_addr);
    my ($this, $this_addr, $this_addr, $foo);

    my $sockaddr = 'S n a4 x8';

    ($name, $aliases, $proto) = getprotobyname ('tcp');
    my $tcp = $proto;
    #($name, $aliases, $port, $proto) = getservbyname ('www', 'tcp');

    chop (my $this_host = `hostname`);
    ($name, $aliases, $addrtype, $length, $this_addr) = gethostbyname ($this_host);
    die "$this_host: unknown host\n" unless $name;
    ($name, $aliases, $addrtype, $length, $that_addr) = gethostbyname ($that_host);
    die "$that_host: unknown host\n" unless $name;

    $this = pack ($sockaddr, AF_INET, 0, $this_addr);
    $that = pack ($sockaddr, AF_INET, $that_port, $that_addr);

    my $socket;

    while (1)
    {
	$socket = new FileHandle;
	socket($socket, AF_INET, SOCK_STREAM, $foo) || die "socket: $!";
	connect($socket, $that) && last;
	print "$that_host:$that_port: $!; retrying...\n";
	sleep(5);
    }

    $old = select ($socket);
    $| = 1;
    select ($old);
    $socket;
}

sub disconnect
{
    my ($sock) = @_;
    close ($sock);
}

sub create_pixmap_d
{
    my (@data) = @_;
    my ($x, $m) = Gtk::Gdk::Pixmap->create_from_xpm_d($mw->window, undef, @data);
    new Gtk::Pixmap $x, $m;
}

sub create_pixmap_and_mask
{
    my (@data) = @_;
    Gtk::Gdk::Pixmap->create_from_xpm_d($mw->window, undef, @data);
}

sub copyleft
{
    return <<EOF;
MeBay version $version, Copyright (C) 2000 Gargola Software
MeBay comes with ABSOLUTELY NO WARRANTY. This is free software,
and you are welcome to redistribute it under certain conditions.
More details available at http://www.gnu.org/copyleft/copyleft.html
Visit the MeBay website at http://mebay.doit.org/
Send questions, comments, and bug reports to <boyns\@doit.org>
EOF
}

