=gmbplugin DESKTOPCOUCH
name	Desktopcouch
title	Desktopcouch import/export tool
desc	Allows user to import/export configs with desktopcouch, require password and user, if you want set port use couchdb version
req	perl(Net::DBus, CouchDB::Client::DB, Digest::MD5)
=cut

package GMB::Plugin::DESKTOPCOUCH;

use CouchDB::Client;
use Digest::MD5;

use warnings;
use constant
{
    OPT	=> 'PLUGIN_DESKTOPCOUCH_',
    RECORD => "https://github.com/hugosenari/zeitgeist-extensions/wiki/cfg",
    APP => "application://gmusicbrowser.desktop",
    VERSION => 0.1,
    ERROR => 100,
    INFO => 10,
    DEBUG => 0,
    LOG_LEVEL => 10
};

my $bus=$GMB::DBus::bus;
my $Log=Gtk2::ListStore->new('Glib::String');

sub GetPort
{
    # Get a handle to the desktopcouch service
    my $desktopcouchs = $bus->get_service("org.desktopcouch.CouchDB");
    my $desktopcouch = $desktopcouchs->get_object("/",
					"org.desktopcouch.CouchDB");
    return $desktopcouch->getPort();
}

sub Log
{	my $text=shift;
        my $level=shift;
        if ($level >= LOG_LEVEL || $::debug)
        {
            $Log->set( $Log->prepend,0, "Couchdb::".$level."::".localtime()."::$text" );
            if (my $iter=$Log->iter_nth_child(undef,30))
                { $Log->remove($iter); }
	    print "Couchdb::".$level."::".localtime()."::$text\n";
	} else {
	    warn "Couchdb::".$level."::".localtime()."::$text\n" if $::debug;
	}
	
}

sub Error {Log(shift, ERROR)}
sub Info {Log(shift, INFO)}
sub Debug {Log(shift, DEBUG)}

my $handle;

sub Init
{
        Info("Plugin initialized");
}

sub Start
{
        Info("Plugin started");
        ImportFromCouchdb() if defined $::Options{OPT.'ATINIT'} && $::Options{OPT.'ATINIT'};
        $handle={};
        ::Watch($handle, Save => \&BeforeSave)
}

sub BeforeSave
{
	eval
        {
	    Info("Exporting before Save") if defined $::Options{OPT.'ATSAVE'} && $::Options{OPT.'ATSAVE'};
	    ExportToCouchdb() if defined $::Options{OPT.'ATSAVE'} && $::Options{OPT.'ATSAVE'};
	}or do{
	    return 0;  
	};
        return 1;
}

sub Stop
{
        ::UnWatch($handle, 'Save');
        Info("Plugin stoped");
}

sub prefbox 
{
        #default options
        $::Options{OPT.'PROTOCOL'}= "http://" unless defined $::Options{OPT.'PROTOCOL'};
        $::Options{OPT.'HOST'}="localhost" unless defined $::Options{OPT.'HOST'};
        $::Options{OPT.'DBNAME'}="appsconfigs" unless defined $::Options{OPT.'DBNAME'};
        $::Options{OPT.'PORT'}=GetPort();
        #options fields
	my $protocol=::NewPrefEntry(OPT.'PROTOCOL', "protocol:", tip => "http or https");
	my $username=::NewPrefEntry(OPT.'USER', "username:", tip => "can be empty");
	my $password=::NewPrefEntry(OPT.'PASS', "password:",hide => 1, tip => "can be empty");
        my $lbox=::Vpack($protocol,$username,$password);
        my $dbhost=::NewPrefEntry(OPT.'HOST', "couchdb host:", tip => "ie: localhost");
        my $dbname=::NewPrefEntry(OPT.'DBNAME', "couchdb database:", tip => "ie: gmusicbrowser");
        my $rbox=::Vpack($dbhost,$dbname);
        my $fields=::Hpack($rbox,$lbox);
        #checks
        my $atinit=::NewPrefCheckButton(OPT.'ATINIT', "import when open GMB:", tip => "Import when program starts");
        my $atsave=::NewPrefCheckButton(OPT.'ATSAVE', "export when GMB save cfg:", tip => "Export before program save configs");
        my $checks=::Hpack($atinit,$atsave);
        #buttons
        my $import=::NewIconButton('gtk-refresh', "Import",\&ImportFromCouchdb);
        my $export=::NewIconButton('gtk-refresh', "Export",\&ExportToCouchdb);
        my $buttons=::Hpack($import,$export);
        #packing all
        my $vbox=::Vpack($fields,$checks, $buttons);
        $vbox->add(::LogView($Log));
        Debug('Packing config');
	return $vbox;
}

sub GetUriWithoutPass
{
    return $::Options{OPT.'PROTOCOL'}.$::Options{OPT.'HOST'}.':'.$::Options{OPT.'PORT'}.'/'.$::Options{OPT.'DBNAME'};
}

sub GetUri
{
    my $uri = $::Options{OPT.'PROTOCOL'};
    if (defined $::Options{OPT.'USER'} && defined $::Options{OPT.'PASS'})
    {
        $uri = $uri.$::Options{OPT.'USER'}.':'.$::Options{OPT.'PASS'}.'@';
    }
    $uri = $uri.$::Options{OPT.'HOST'};
    $uri = $uri.':'.$::Options{OPT.'PORT'} if defined $::Options{OPT.'PORT'};
    return $uri;
}

my $dbc = undef;
my $dbcuri = undef;
sub GetCouchdbCli
{
    my $uri = GetUri();
    if(defined $dbcuri && $dbcuri eq $uri)
    {
        Debug("Reuse client to: ".$uri);
        return $dbc;
    } else {
        Debug("Create client to: ".$uri);
        $dbc = CouchDB::Client->new(uri => $uri);
        $dbcuri = $uri;
        return $dbc;
    }
}


my $db = undef;
my $dbname = undef;
sub GetCouchdbDB
{
    #verify if db connection exist, and if database name diff
    if (defined $db && $dbname ne $::Options{OPT.'DBNAME'})
    {
        $db = undef;
        $db = GetCouchdbDB();
	Info("Using database ".$::Options{OPT.'DBNAME'});
    }else
    #create new connection
    {
        my $cdb = GetCouchdbCli()->newDB($::Options{OPT.'DBNAME'});
        #try to create new db or that exist
        eval
        {
            $bd = $cdb->create();
            1;
        } or do{
            $bd = $cdb;
        };
        $dbname = $::Options{OPT.'DBNAME'};
        Debug('Reusing database '.$::Options{OPT.'DBNAME'});
    }
    Debug("Using database ".$::Options{OPT.'DBNAME'});
    return $bd;
}

sub ExportToCouchdb
{
    Info('Start exporting: '.GetUriWithoutPass());
    @docs = ();
    while (($key, $value) = each(%::Options)){
        my $doc = OptionToDoc($key, $value);
        if (defined $doc)
        {
            push @docs, ($doc);
        } else{
            Debug('Do not export: '.$key);
        }
    }
    $size = @docs;
    Info('Complete exporting: '.GetUriWithoutPass().', exported '.$size.' configs');
    return $docs;
}

sub OptionToDoc
{
    my $key=shift;
    my $value=shift;
    Debug('Converting option in doc: '.$key);
    my $docId = DocIdFromKey($key);
    my $couchdb = GetCouchdbDB();
    my $result = undef;
    if($couchdb->docExists($docId))
    {
        my $results = $couchdb->listDocs(key=>$docId);
        foreach $result (@$results)
        {
	    $result->retrieve();
	    $data = $result->data();
	    unless (CompareValues($data->{value}, $value))
	    {
		$data->{value} = $value;
		$result->data($data);
		Debug('Config option doc exist and need update: '.$data->{name}.' as '.$docId);
		$result->update()
	    }
        }
    } else {
        Debug('Creating new config option doc: '.$key.' as '.$docId);
        $result = $couchdb->newDoc($docId, undef,
            {
                name=>$key,
                value=>$value,
                record_type=>RECORD,
                app=>APP,
                application_annotations=>{
                    gmusicbrowser=>{
                        plugin_version=>VERSION
                    }
                }
            }
        );
	$result->create();
    }
    Debug('Converted option in doc: '.$key.' as '.$docId);
    return $result;
}

sub ImportFromCouchdb
{
    Info('Start importing from: '.GetUriWithoutPass());
    @opts = ();
    while (($key, $value) = each(%::Options)){
        my $optval = DocToOption($key);
        if (defined $optval)
        {
            push @opts, ($optval);
        }
    }
    $size = @opts;
    Info('Complete importing from: '.GetUriWithoutPass(). ', imported '. $size .' options');
    return $opts
}

sub DocToOption
{
    my $key = shift;
    my $docId = DocIdFromKey($key);
    Debug('Converting doc in option: '.$key.' as '.$docId);
    my $couchdb = GetCouchdbDB();
    my $result = undef;
    if($couchdb->docExists($docId))
    {
        my $results = $couchdb->listDocs(key=>$docId);
        foreach my $r (@$results)
        {
	    $result = $r;
	    $result->retrieve();
	    $data = $result->data();
	    if (CompareValues($data->{value}, $::Options{$key}))
	    {
		$result = undef;
	    } else {
		Debug('Config option doc exist: '.$data->{name}.' as '.$docId);
		$::Options{$key} = $data->{value};
	    }
        }
    } else {
        Debug('Cannot find '.$key.' at couchdb, as '.$docId);
    }
    return $result;
}

sub DocIdFromKey
{
    return Digest::MD5::md5_hex(APP.'/'.shift);
}

sub CompareValues
{
    $vala = shift;
    $valb = shift;
    if (defined $vala && defined $valb)
    {
	return 0 if ref $vala ne ref $valb;
	return Digest::MD5::md5_hex($vala) eq Digest::MD5::md5_hex($valb);
    } else {
	#warn 'both are undefined they are equals';
	return 1 unless defined $valb;
    }
    return 0;
}

1 #the file must return true