#!/usr/bin/env perl

use warnings;
use strict;

use CGI ();
use Data::Dumper;
use DBI;


my $q = CGI->new;
my $dbh = DBI->connect("dbi:Pg:dbname=intertubes", '', '');

my $base_url = 'http://' . $q->virtual_host() . ':' . $q->virtual_port() . $q->script_name();

sub lookup_slug {
    my ($slug) = @_;
    $dbh->selectrow_array("SELECT slug,url FROM links WHERE slug = ?;", {}, $slug);
}

sub lookup_url {
    my ($url) = @_;
    $dbh->selectrow_array("SELECT slug,url FROM links WHERE url = ?;", {}, $url);
}

sub preview_enabled {
    return ($q->cookie('preview') || 'false') eq 'true';
}

sub preview_links {
    my ($href, $text) =
        preview_enabled() ? ('/disable-preview', "Disable Preview")
                          : ('/enable-preview',  "Enable Preview");
    $q->a({-href => $base_url . $href}, $text);
}

sub link_slug {
    my ($slug) = @_;
    my $url = $base_url . "/" . $slug;
    $q->a({-href=>$url}, $url);
}

sub basic_page {
    my ($params) = @_;

    my $title = $params->{-title};
    my $body = $params->{-body};

    print $q->header(-status => $params->{-status} || 200),
          $q->start_html({-title => $title, -style =>{'src' => '/style.css'}});
    print $q->div({-class => 'divitis'},
                  $q->h1("The Intertubes"),
                  $body,
                  $q->div({-class => 'footer'},
                          preview_links));

    print $q->end_html();
}

sub success_page {
    my ($params) = @_;

    my $url   = $params->{-url};
    my $text  = $params->{-text}  || "now redirects to";
    my $class = $params->{-class} || "success";

    basic_page { -title => $params->{-title},
                 -body => $q->div({-class => $class},
                                  $q->h3(link_slug($params->{-slug})),
                                  $q->p($text),
                                  $q->h3($q->a({-href=>$url}, $url)))};
}

sub error_page {
    my ($params) = @_;

    basic_page { -title  => $params->{-title},
                 -body   => $q->p({-class=>'error'}, $params->{-text}),
                 -status => $params->{-status}};
}

sub create_page {
    basic_page { -title => "create",
                 -body => $q->start_form({-method=>"post",-action=>$base_url . "/create"}) .
                          $q->input({-name=>"url"}) .
                          $q->end_form() };
}

sub url_filter {
    my ($url) = @_;

    return if ($url !~ /\./);

    if ($url =~ m{^https?://}) {
        $url;
    }
    else {
        "http://" . $url;
    }
}

sub set_preview_to {
    my ($to) = @_;
    print $q->redirect(-uri=>$base_url, -cookie=>$q->cookie('preview', $to));
}

sub find_available_slug {
    for (0 .. 5) {
        my $slug = generate_link_name();
        return $slug unless lookup_slug($slug);
    }
    undef;
}

sub add_url {
    my $url = url_filter($q->param('url'));
    my $ip = $q->remote_addr;

    if (!$url) {
        basic_page { -title => "invalid",
                     -body => $q->p({-class=>"error"},
                                    "Cannot link to that URL") };
    }
    else {
        my ($slug,$existing_url) = lookup_url($url);
        if ($slug && $existing_url) {
            success_page { -title => "created", -slug => $slug, -url => $url };
        }
        else {
            my $slug = find_available_slug() or die "Couldn't find free slug";

            $dbh->do("INSERT INTO links (slug,url,creator) VALUES (?,?,?);", {}, ($slug, $url, $ip))
                or die("Couldn't insert link");

            success_page { -title => "created", -slug => $slug, -url => $url };
        }
    }
}

sub record_redirect {
    my ($slug) = @_;
    my $ip = $q->remote_addr;
    my $referer = $q->referer;
    $dbh->do("INSERT INTO hits (ip,referer,slug) VALUES (?,?,?);", {}, ($ip, $referer, $slug))
        or die("Aaargh");
}

sub redirect {
    my ($slug) = @_;
    my ($existing_slug,$url) = lookup_slug($slug);
    if ($existing_slug && $url) {
        record_redirect($slug);
        if (preview_enabled) {
            success_page { -title => "created", -slug => $slug, -url => $url,
                           -text => "redirects to", -class => "preview" };
        }
        else {
            print $q->redirect($url);
        }
    }
    else {
        error_page { -title => "error", -text => 'No such short url "' . $slug . '"' };
    }
}

my @slug_parts = split //, "1234567890asdfghijklmnopqrstuvwxyz";
my $slug_size = 6;

sub generate_link_name {
    my $l = @slug_parts;
    my $res = "";
    for (1 .. $slug_size) {
        $res .= $slug_parts[rand($l)];
    }
    $res;
}

sub route {
    $_ = $q->path_info();
    if ($q->request_method eq "POST" && m{^/create}) {
        add_url();
    }
    elsif (m{^/disable-preview}) { set_preview_to "false"; }
    elsif (m{^/enable-preview}) { set_preview_to "true"; }
    elsif (m|^/([1-9a-z]{6})|) { redirect($1); }
    elsif (m{^/$} || m{^$}) { create_page; }
    else {
        error_page { -title => "error: 404", -text => "Page not found", -status => 404 }
    }
}

eval {
    route();
} or do {
    error_page { -title => "error", -text => "$@" };
};
# print Dumper($q->param);
# print url_filter("asdf");
# print generate_link_name();
# success_page { -slug => "slug", -url => "foo" };
