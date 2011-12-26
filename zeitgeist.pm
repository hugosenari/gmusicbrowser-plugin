# The code of this plugins came from nowplaying.pm and mpris2.pm plugins from gmusicbrowser
#
#Copyright (C) 2005-2009 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

# the plugin file must have the following block before the first non-comment line,
# it must be of the format :
# =gmbplugin PID
# name	short name
# title	long name, the short name is used if empty
# desc	description, may be multiple lines
# =cut
=gmbplugin ZEITGEIST
name	Zeitgeist
title	Zeitgeist feeders
desc	Feed Zeitgeist when playing a song
=cut

# the plugin package must be named GMB::Plugin::PID (replace PID), and must have these sub :
# Start	: called when the plugin is activated
# Stop	: called when the plugin is de-activated
# prefbox : returns a Gtk2::Widget used to describe the plugin and set its options

package GMB::Plugin::ZEITGEIST;
use strict;
use warnings;
use constant
{	OPT	=> 'PLUGIN_ZEITGEIST_',
};
my $Log=Gtk2::ListStore->new('Glib::String');

my $bus=$GMB::DBus::bus;
die "Requires DBus support to be active\n" unless $bus; #only requires this to use the hack in gmusicbrowser_dbus.pm so that Net::DBus::GLib is not required, else could do just : use Net::DBus::GLib; $bus=Net::DBus::GLib->session;

my $handle;
my $stoped = undef;

sub Start
{	$handle={};	#the handle to the Watch function must be a hash ref, if it is a Gtk2::Widget, UnWatch will be called when the widget is destroyed
	::Watch($handle, PlayingSong	=> \&Changed);
}
sub Stop
{	::UnWatch($handle,'PlayingSong');
}

sub Log
{	my $text=$_[0];
	$Log->set( $Log->prepend,0, localtime().'  '.$text );
	warn "$text\n" if $::debug;
	if (my $iter=$Log->iter_nth_child(undef,50)) { $Log->remove($iter); }
}

sub prefbox 
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	$vbox->add( ::LogView($Log) );
	return $vbox;
}

use Net::DBus ':typing';

sub Changed
{

        eval {
                # Get a handle to the Zeitgeist service
                my $zeitgeist = $bus->get_service("org.gnome.zeitgeist.Engine");
        
                # Get the device manager
                my $logger = $zeitgeist->get_object("/org/gnome/zeitgeist/log/activity",
                                                    "org.gnome.zeitgeist.Log");
                #http://zeitgeist-project.com/docs/0.7.1/dbus_api.html
                eval {
                        #METADATA
                        my $timestamp = time();
                        my $interpretation = dbus_string('http://www.zeitgeist-project.com/ontologies/2010/01/27/zg#AccessEvent'); #ACCESS_EVENT
                        my $manifestation = dbus_string('http://www.zeitgeist-project.com/ontologies/2010/01/27/zg#ScheduledActivity'); #SCHEDULED_ACTIVITY
                        my $actor = dbus_string('application://gmusicbrowser.desktop'); #GMUISIC_BROWSER
                        my $metadata = dbus_array([
                                '', #id undefined
                                $timestamp,
                                $interpretation,
				
                                $manifestation,
                                $actor,
                                dbus_string('')
                        ]);
                
                        #SUBJECT
                        return unless defined $::SongID;
                        my ($title,$album,$artist,$track,$uri)= Songs::Get($::SongID,qw/title album artist track uri length/);
                        my $dirPath = $uri;
                        $dirPath =~ s/\/[^\/]+$/\//g;
                        my $subjectUri = dbus_string($uri); #uri file://+path
                        my $subjectInterpretation = dbus_string('http://www.semanticdesktop.org/ontologies/2007/03/22/nfo#Audio'); #AUDIO
                        my $subjectManifestation = dbus_string('http://www.semanticdesktop.org/ontologies/2007/03/22/nfo#FileDataObject'); #FILE_DATA_OBJECT
                        my $subjectOrign = dbus_string($dirPath); #dir from
                        my $subjectMineType= dbus_string('audio/mpeg'); #minetype
                        my $subjectText = dbus_string("$title - $artist - $album - $track"); #display subject text
                        my $subjectStorage = dbus_string('local'); #uuid from storage
                        my $subject = dbus_array([
                                $subjectUri,
                                $subjectInterpretation,
                                $subjectManifestation,
				
                                $subjectOrign,
                                $subjectMineType,
                                $subjectText,
				
                                $subjectStorage,
                                $subjectUri
                        ]);
                        #subjects
                        my $subjects =  dbus_array([$subject]);
                        #bytes
                        my $bytes = dbus_array([]); #array of bytes
                        #event
                        my $event = dbus_struct([
                                $metadata,
                                $subjects,
                                $bytes
                        ]);
                        #events
			my $events = dbus_array([$event]);
                        
                        eval {
                                #send to zeitgeist
                                $logger->InsertEvents($events);
                                Log("Song logged: $title - $artist - $album - $track");
				return 1;
                        } or do {
                                Log("Cannot send metadata to zeitgeist, Error: $@");
                                return 0;
                        };
			return 1;
                } or do {
                        Log("Cannot prepare metadata to send, Error: $@");
                        return 0;
                };
		return 1;
        } or do {
                Log("Cannot connect to zeitgeist dbus object, Error: $@");
                return 0;
        };
        return 1;
}


1 #the file must return true