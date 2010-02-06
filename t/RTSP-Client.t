#!/usr/bin/env perl

use Test::More tests => 8;
BEGIN { use_ok('RTSP::Client') };

# to test, pass url of an RTSP server in $ENV{RTSP_CLIENT_TEST_URI}
# e.g.   RTSP_CLIENT_TEST_URI="rtsp://10.0.1.105:554/mpeg4/media.amp" perl -Ilib t/RTSP-Client.t
my $uri = $ENV{RTSP_CLIENT_TEST_URI};

SKIP: {
    skip "No RTSP server URI provided for testing", 7 unless $uri;
    
    # parse uri
    my ($host, $port, $media_path) = $uri =~ m!^rtsp://([-\w.]+):?(\d+)?(/.+)$!ism;
    skip "Invalid RTSP server URI provided for testing", 7 unless $host && $media_path;
    
    my $client = new RTSP::Client(
        address => $host,
        port => $port,
        media_path => $media_path,
        debug => 0,
        print_headers => 0,
    );

    $client->open or die $!;
    pass("opened connection to RTSP server");
    
    my @public_options = $client->options_public;
    ok(@public_options, "got public allowed methods: " . join(', ', @public_options));
    
    ok($client->play, "play");
        
    # it's ok if these return 405 (method not allowed)
    {
        my $status;

        $client->pause;
        $status = $client->request_status;
        ok(($status == 200 || $status == 405), "pause");

        $client->stop;
        $status = $client->request_status;
        ok(($status == 200 || $status == 405), "stop");
        
    }
    
    ok($client->describe, "got SDP info");
    ok($client->teardown, "teardown");
};

