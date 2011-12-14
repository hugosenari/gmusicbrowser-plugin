

use Data::Dumper;
use Net::DBus;
use Net::DBus ':typing';

my $bus=Net::DBus->session;

sub Log
{	my $text=$_[0];
	print "$text\n";
}

sub Send
{
        eval {
                # Get a handle to the Zeitgeist service
                my $zeitgeist = $bus->get_service("org.gnome.zeitgeist.Engine");
        
                # Get the device manager
                my $logger = $zeitgeist->get_object("/org/gnome/zeitgeist/log/activity",
                                                    "org.gnome.zeitgeist.log");

                #http://zeitgeist-project.com/docs/0.7.1/dbus_api.html
                eval {
                        #METADATA
                        my $time = time();
                        my $interpretation = dbus_string('http://www.zeitgeist-project.com/ontologies/2010/01/27/zg#AccessEvent'); #ACCESS_EVENT
                        my $manifestation = dbus_string('http://www.zeitgeist-project.com/ontologies/2010/01/27/zg#ScheduledActivity'); #SCHEDULED_ACTIVITY
                        my $actor = dbus_string('app://gmusicbrowser.desktop'); #GMUISIC_BROWSER
                        my $metadata = dbus_array((
                                dbus_string(''), #id undefined
                                $time,
                                $interpretation,
                                
                                $manifestation,
                                $actor,
                                dbus_string('')
                        ));
                
                        #SUBJECT
                        my ($title,$album,$artist,$track,$uri)= (
                            'titulo de teste', 'album teste', 'artista teste', 1, 'file://home/hugosenari/teste.mp3'
                        );
                        my $dirPath = $uri;
                        $dirPath =~ s/\/[^\/]+$/\//g;
                        my $subjectUri = dbus_string($uri); #uri file://+path
                        my $subjectInterpretation = dbus_string('http://www.semanticdesktop.org/ontologies/2007/03/22/nfo#Audio'); #AUDIO
                        my $subjectManifestation = dbus_string('http://www.semanticdesktop.org/ontologies/2007/03/22/nfo#FileDataObject'); #FILE_DATA_OBJECT
                        my $subjectOrign = dbus_string($dirPath); #dir from
                        my $subjectMineType= dbus_string('audio/mpeg'); #minetype
                        my $subjectText = dbus_string("$title - $artist - $album - $track"); #display subject text
                        my $subjectStorage = dbus_string('unknown'); #uuid from storage
                        my $subject = dbus_array((
                                $subjectUri,
                                $subjectInterpretation,
                                $subjectManifestation,
                                $subjectOrign,
                                $subjectMineType,
                                $subjectText,
                                $subjectStorage,
                                $subjectUri,
                        ));
                        #subjects
                        my $subjects =  dbus_array(($subject));
                        #bytes
                        my $bytes = dbus_array(()); #array of bytes
                        #event
                        my $event = dbus_struct(
                                $metadata,
                                $subjects,
                                $bytes
                        );
                        #events
                        my $events = dbus_array(($event));
                        eval {
                                #send to zeitgeist
                                $logger->InsertEvents($events);
                                Log("Song logged: $title - $artist - $album - $track");
                        } or do {
                                Log("Cannot send metadata to zeitgeist, Error: $@");
                                return 1;
                        };
                } or do {
                        Log("Cannot prepare metadata to send, Error: $@");
                        return 1;
                };
                
        } or do {
                Log("Cannot connect to zeitgeist dbus object, Error: $@");
                return 1;
        };
        return 1;
}
Send();

#[
#    (
#        [
#            u'1',
#            u'1315713565000',
#            u'http://www.zeitgeist-project.com/ontologies/2010/01/27/zg#CreateEvent',

#            u'http://www.zeitgeist-project.com/ontologies/2010/01/27/zg#UserActivity',
#            u'application://file-roller.desktop',
#            u''
#        ],
#        [
#            [
#                u'file:///home/hugosenari/Downloads/web.7z',
#                u'http://www.semanticdesktop.org/ontologies/2007/03/22/nfo#Archive',
#                u'http://www.semanticdesktop.org/ontologies/2007/03/22/nfo#FileDataObject',
#                u'file:///home/hugosenari/Downloads',

#                u'application/x-7z-compressed',
#                u'web.7z',
#                u'unknown',
#                u'file:///home/hugosenari/Downloads/web.7z']
#            ],
#        [
#        ]
#    )
#]
#_parse_node->new->_parse_node...
#new->_parse_node->_parse_interface->_parse_method->_parse_type