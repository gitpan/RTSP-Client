package RTSP::Client;

use RTSP::Lite;
use Moose;

our $VERSION = '0.1';

=head1 NAME

RTSP::Client - High-level client for the Real-Time Streaming Protocol

=head1 SYNOPSIS

  use RTSP::Client;
  my $client = new RTSP::Client(
      port               => 554,
      client_port_range  => '6970-6971',
      transport_protocol => 'RTP/AVP;unicast',
      address            => '10.0.1.105',
      media_path         => '/mpeg4/media.amp',
  );

  $client->open or die $!;

  $client->play;
  $client->pause;
  $client->stop;
  
  my $sdp = $client->describe;
  my @allowed_public_methods = $client->options_public;
  
  $client->teardown;
  
  
=head1 DESCRIPTION

This module provides a high-level interface for communicating with an RTSP server.
RTSP is a protocol for controlling streaming applications, it is not a media transport or a codec. 
It supports describing media streams and controlling playback, and that's about it.

In typical usage, you will open a connection to an RTSP server and send it the PLAY method. The server
will then stream the media at you on the client port range using the specified transport protocol.
You are responsible for listening on the client port range and handling the actual media data yourself,
actually receiving a media stream or decoding it is beyond the scope of RTSP and this module.

=head2 EXPORT

No namespace pollution here!

=head2 ATTRIBUTES

=over 4

=item session_id

RTSP session id. It will be set on a successful OPEN request and added to each subsequent request

=cut
has session_id => (
    is => 'rw',
    isa => 'Str',
);

=item client_port_range

Ports the client receives data on. Listening and receiving data is not handled by RTSP::Client

=cut
has client_port_range => (
    is => 'rw',
    isa => 'Str',
    default => '6970-6971',
);

=item media_path

Path to the requested media stream

e.g. /mpeg4/media.amp

=cut
has media_path => (
    is => 'rw',
    isa => 'Str',
    default => '/',
);

=item transport_protocol

Requested transport protocol, RTP by default

=cut
has transport_protocol => (
    is => 'rw',
    isa => 'Str',
    default => 'RTP/AVP;unicast',
);

=item address

RTSP server address. This is required.

=cut
has address => (
    is => 'rw',
    isa => 'Str',
    required => 1,
);

=item port

RTSP server port. Defaults to 554

=cut
has port => (
    is => 'rw',
    isa => 'Int',
    default => 554,
);

=item connected

Is the client connected?

=cut
has connected => (
    is => 'rw',
    isa => 'Bool',
);

=item print_headers

Print out debug headers

=cut
has print_headers => (
    is => 'rw',
    isa => 'Bool',
);

=item debug

Print debugging information (request status)

=cut
has debug => (
    is => 'rw',
    isa => 'Bool',
);

# RTSP::Lite client
has _rtsp => (
    is => 'rw',
    isa => 'RTSP::Lite',
    default => sub { RTSP::Lite->new },
);

=back

=head1 METHODS

=over 4

=cut

# construct uri to media
sub _request_uri {
    my ($self) = @_;
    return "rtsp://" . $self->address . ':' . $self->port . $self->media_path;
}

=item open

This method opens a connection to the RTSP server and does a SETUP request. Returns true on success, false with $! possibly set on failure.

=cut
sub open {
    my ($self) = @_;
    
    # open connection, returns $! set on failure
    $self->_rtsp->open($self->address, $self->port)
        or return;
            
    # request transport
    my $proto = $self->transport_protocol;
    my $ports = $self->client_port_range;
    my $transport_req_str = join(';', $proto, "client_port=$ports");
    $self->_rtsp->add_req_header("Transport", $transport_req_str);

    return unless $self->request('SETUP');
        
    # get session ID
    my $se = $self->_rtsp->get_header("Session");
    my $session = @$se[0];
    
    if ($session) {
        $self->session_id($session);
        $self->_rtsp->add_req_header("Session", $session);
    }
    
    $self->connected($session ? 1 : 0);
    
    return $session ? 1 : 0;
}

=item play

A PLAY request will cause one or all media streams to be played. Play requests can be stacked by sending multiple PLAY requests. The URL may be the aggregate URL (to play all media streams), or a single media stream URL (to play only that stream). A range can be specified. If no range is specified, the stream is played from the beginning and plays to the end, or, if the stream is paused, it is resumed at the point it was paused.

=cut
sub play {
    my ($self) = @_;
    return unless $self->connected;
    return $self->request('PLAY');
}

=item pause

A PAUSE request temporarily halts one or all media streams, so it can later be resumed with a PLAY request. The request contains an aggregate or media stream URL.

=cut
sub pause {
    my ($self) = @_;
    return unless $self->connected;
    return $self->request('PAUSE');
}

=item record

The RECORD request can be used to send a stream to the server for storage.

=cut
sub record {
    my ($self) = @_;
    return unless $self->connected;
    return $self->request('RECORD');
}

=item teardown

A TEARDOWN request is used to terminate the session. It stops all media streams and frees all session related data on the server.

=cut
sub teardown {
    my ($self) = @_;
    return unless $self->connected;
    $self->connected(0);
    return $self->request('TEARDOWN');
}

sub options {
    my ($self) = @_;
    return unless $self->connected;
    return $self->request('OPTIONS');
}

=item options_public

An OPTIONS request returns the request types the server will accept.

This returns an array of allowed public methods.

=cut
sub options_public {
    my ($self) = @_;
    return unless $self->options;
    my $public = $self->_rtsp->get_header('Public');
    return $public ? @$public : undef;
}

=item describe

The reply to a DESCRIBE request includes the presentation description, typically in Session Description Protocol (SDP) format. Among other things, the presentation description lists the media streams controlled with the aggregate URL. In the typical case, there is one media stream each for audio and video.

This method returns the actual DESCRIBE content, as SDP data

=cut
sub describe {
    my ($self) = @_;
    return unless $self->connected;
    return unless $self->request('DESCRIBE');
    return $self->_rtsp->body;
}

=item request_status

Get the status code of the last request (e.g. 200, 405)

=cut
sub request_status {
    my ($self) = @_;
    return $self->_rtsp->status;
}

=item request($method)

Sends a $method request, returns success

=cut
sub request {
    my ($self, $method) = @_;
        
    $self->_rtsp->method(uc $method);
    
    # request media
    my $req_uri = $self->_request_uri;
    $self->_rtsp->request($req_uri)
        or return;
        
    # request status
    my $status = $self->_rtsp->status;
    if ($self->debug) {
        print "Status: $status " . $self->_rtsp->status_message . "\n";
    }
    if (! $status || $status != 200) {
        return;
    }
    
    if ($self->print_headers) {
        my @headers = $self->_rtsp->headers_array;
        my $body = $self->_rtsp->body;
        print "$_\n" foreach @headers;
        print "$body\n" if $body;
    }
    
    return 1;
}

# clean up connection if we're still connected
sub DEMOLISH {
    my ($self) = @_;
    return unless $self->connected;
    $self->teardown;
}

no Moose;
__PACKAGE__->meta->make_immutable;

=back

=head1 SEE ALSO

L<RTSP::Lite>, L<http://en.wikipedia.org/wiki/Real_Time_Streaming_Protocol>

=head1 AUTHOR

Mischa Spiegelmock E<lt>revmischa@cpan.orgE<gt>

=head1 ACKNOWLEDGEMENTS

This is based entirely on L<RTSP::Lite> by Masaaki Nabeshima.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Mischa Spiegelmock

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.


=cut
