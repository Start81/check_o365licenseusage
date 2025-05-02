#!/usr/bin/perl -w
#===============================================================================
# Script Name   : check_o365licenseusage.pl
# Usage Syntax  : check_o365licenseusage.pl [-v] -T <TENANTID> -I <CLIENTID> -p <CLIENTSECRET> [-N <LICENSENAME>] [-w <WARNING>] [-c <CRITICAL>] 
# Author        : DESMAREST JULIEN (Start81)
# Version       : 1.0.2
# Last Modified : 27/05/2024
# Modified By   : DESMAREST JULIEN (Start81)
# Description   : check o365 License usage
# Depends On    : REST::Client, Data::Dumper,  Monitoring::Plugin, File::Basename, JSON, Readonly, URI::Encode
#
# Changelog:
#    Legend:
#       [*] Informational, [!] Bugix, [+] Added, [-] Removed
# - 13/03/2024 | 1.0.0 | [*] initial realease
# - 27/05/2024 | 1.0.1 | [*] Improve output format
# - 02/05/2025 | 1.0.2 | [*] Add some token format check
#===============================================================================
use REST::Client;
use Data::Dumper;
use JSON;
use utf8;
use File::Basename;
use strict;
use warnings;
use Readonly;
use Monitoring::Plugin;
use URI::Encode;
Readonly our $VERSION => '1.0.1';
my $graph_endpoint = "https://graph.microsoft.com";
my @licenses_name = ();
my @criticals = ();
my @warnings = ();
my @unknown = ();
my @ok = ();
my $result;
my $o_verb;
sub verb { my $t=shift; print $t,"\n" if ($o_verb) ; return 0}
my $me = basename($0);
my $client = REST::Client->new();
my $np = Monitoring::Plugin->new(
    usage => "Usage: %s  [-v] -T <TENANTID> -I <CLIENTID> -p <CLIENTSECRET> [-N <LICENSENAME>] [-w <WARNING>] [-c <CRITICAL>]   \n ",
    plugin => $me,
    shortname => " ",
    blurb => "$me check o365 License usage",
    version => $VERSION,
    timeout => 30
);
#Source https://learn.microsoft.com/en-us/entra/identity/users/licensing-service-plan-reference
my %skuPartNumber = ('VISIOCLIENT' => 'Visio Online Plan 2',
    'STREAM' => 'Microsoft Stream',
    'FLOW_PER_USER' => 'Power Automate per user plan',
    'POWER_BI_PRO' => 'Power BI Pro',
    'WINDOWS_STORE' => 'Windows Store for Business',
    'ENTERPRISEPACK' => 'Office 365 E3',
    'FLOW_FREE' => 'Microsoft Power Automate Free',
    'MICROSOFT_BUSINESS_CENTER' => 'Microsoft Business Center' ,
    'CCIBOTS_PRIVPREV_VIRAL' => 'Power Virtual Agents Viral Trial',
    'POWERAPPS_VIRAL' => 'Microsoft Power Apps Plan 2 Trial' ,
    'EXCHANGESTANDARD' => 'Exchange Online (Plan 1)',
    'Microsoft_Teams_Exploratory_Dept' => 'Microsoft Teams Exploratory',
    'POWER_BI_STANDARD' => 'Microsoft Fabric (Free)',
    'OFFICESUBSCRIPTION' => 'Microsoft 365 Apps for enterprise',
    'SPE_E5' => 'Microsoft 365 E5',
    'MCOMEETADV' => 'Microsoft 365 Audio Conferencing' ,
    'AAD_PREMIUM' => 'Microsoft Entra ID P1',
    'PROJECTPROFESSIONAL' => 'Project Plan 3',
    'POWERAPPS_DEV' => 'Microsoft PowerApps for Developer',
    'STANDARDPACK' => 'Office 365 E1',
);
#write content in a file
sub write_file {
    my ($content,$tmp_file_name) = @_;
    my $fd;
    verb("write $tmp_file_name");
    if (open($fd, '>', $tmp_file_name)) {
        print $fd $content;
        close($fd);       
    } else {
        my $msg ="unable to write file $tmp_file_name";
        $np->plugin_exit('UNKNOWN',$msg);
    }
    
    return 0
}

#Read previous token  
sub read_token_file {
    my ($tmp_file_name) = @_;
    my $fd;
    my $token ="";
    my $last_mod_time;
    verb("read $tmp_file_name");
    if (open($fd, '<', $tmp_file_name)) {
        while (my $row = <$fd>) {
            chomp $row;
            $token=$token . $row;
        }
        $last_mod_time = (stat($fd))[9];
        close($fd);
    } else {
        my $msg ="unable to read $tmp_file_name";
        $np->plugin_exit('UNKNOWN',$msg);
    }
    return ($token,$last_mod_time)
    
}

#get a new acces token
sub get_access_token{
    my ($clientid,$clientsecret,$tenantid) = @_;
    verb(" tenantid = " . $tenantid);
    verb(" clientid = " . $clientid);
    verb(" clientsecret = " . $clientsecret);
    my $uri = URI::Encode->new({encode_reserved => 1});
    my $encoded_graph_endpoint = $uri->encode($graph_endpoint . '/.default');
    verb("$encoded_graph_endpoint");
    my $payload = 'grant_type=client_credentials&client_id=' . $clientid . '&client_secret=' . $clientsecret . '&scope='.$encoded_graph_endpoint;
    my $url = "https://login.microsoftonline.com/" . $tenantid . "/oauth2/v2.0/token";
    $client->POST($url,$payload);
    if ($client->responseCode() ne '200') {
        my $msg = "response code : " . $client->responseCode() . " Message : Error when getting token" . $client->{_res}->decoded_content;
        $np->plugin_exit('UNKNOWN',$msg);
    }
    return $client->{_res}->decoded_content;
};

$np->add_arg(
    spec => 'tenant|T=s',
    help => "-T, --tenant=STRING\n"
          . '   The GUID of the tenant to be checked',
    required => 1
);
$np->add_arg(
    spec => 'clientid|I=s',
    help => "-I, --clientid=STRING\n"
          . '   The GUID of the registered application',
    required => 1
);
$np->add_arg(
    spec => 'clientsecret|p=s',
    help => "-p, --clientsecret=STRING\n"
          . '   Access Key of registered application',
    required => 1
);
$np->add_arg(
    spec => 'licensename|N=s', 
    help => "-N, --licensename=STRING\n"  
         . '   name of the license to check let this empty to get all license usage',
    required => 0
);

$np->add_arg(
    spec => 'warning|w=s',
    help => "-w, --warning=threshold\n" 
          . '   See https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT for the threshold format.',
);
$np->add_arg(
    spec => 'critical|c=s',
    help => "-c, --critical=threshold\n"  
          . '   See https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT for the threshold format.',
);
$np->getopts;
my $msg = "";
my $tenantid = $np->opts->tenant;
my $clientid = $np->opts->clientid;
my $clientsecret = $np->opts->clientsecret; 
my $o_license_name = $np->opts->licensename;
my $o_warning = $np->opts->warning;
my $o_critical = $np->opts->critical;
my $status;
my $budget_founded = 0;
$o_verb = $np->opts->verbose if (defined $np->opts->verbose);
my $i = 0;
verb(" tenantid = " . $tenantid);
verb(" clientid = " . $clientid);
verb(" clientsecret = " . $clientsecret);
#Get token
my $tmp_file = "/tmp/$clientid.tmp";
my $token;
my $last_mod_time;
my $token_json;
if (-e $tmp_file) {
    #Read previous token
    ($token,$last_mod_time) = read_token_file ($tmp_file);
    $token_json = from_json($token);
    #check token expiration
    my $expiration =  $last_mod_time + ($token_json->{'expires_in'} - 60);
    my $current_time = time();
    verb "current_time : $current_time   exptime : $expiration\n";
    if ($current_time > $expiration ) {
        #If token is too old
        #get a new token
        $token = get_access_token($clientid,$clientsecret,$tenantid);
		eval {
			$token_json = from_json($token);
		} or do {
			$np->plugin_exit('UNKNOWN',"Failed to decode JSON: $@");
		};
        write_file($token,$tmp_file);
    }
} else {
    #First token
    $token = get_access_token($clientid,$clientsecret,$tenantid);
    eval {
		$token_json = from_json($token);
	} or do {
		$np->plugin_exit('UNKNOWN',"Failed to decode JSON: $@");
	};
    write_file($token,$tmp_file);
}
verb(Dumper($token_json ));
$token = $token_json->{'access_token'};

$client->addHeader('Authorization', 'Bearer ' . $token);
$client->addHeader('Content-Type', 'application/x-www-form-urlencoded');
$client->addHeader('Accept', 'application/json');


my $url = $graph_endpoint . "/v1.0/subscribedSkus";
verb($url);
$client->GET($url);
if($client->responseCode() ne '200'){
    $msg ="response code : " . $client->responseCode() . " Message : Error when getting subscribedSkus " .  $client->responseContent();
    $np->plugin_exit('UNKNOWN',$msg);
}
my $licences_list = from_json($client->responseContent());
verb(Dumper($licences_list));
$i = 0;
my $license_unit = 0;
my $used_license = 0;
my $license_founded = 0;
do {
    $license_unit = 0;
    $used_license = 0;     
    my $product_name = $licences_list->{'value'}->[$i]->{'skuPartNumber'};
    my $display_name = "";
    if ((!$o_license_name) or ($product_name eq  $o_license_name)){
        $license_founded = 1;
        $display_name = "";
        $display_name = $skuPartNumber{$licences_list->{'value'}->[$i]->{'skuPartNumber'}} if (exists $skuPartNumber{$licences_list->{'value'}->[$i]->{'skuPartNumber'}});
        $license_unit = $licences_list->{'value'}->[$i]->{'prepaidUnits'}->{'enabled'} ;
        $used_license = $licences_list->{'value'}->[$i]->{'consumedUnits'};
        if ($license_unit == 0 )
        {
            #push (@unknown,"$product_name prepaidUnits is zero");
            verb ("Skip $product_name prepaidUnits is zero");
        } else {
            $result = (100*$used_license)/$license_unit;
            $np->add_perfdata(label => $product_name . "_usage", value => substr($result,0,5), uom => '%', warning => $o_warning, critical => $o_critical);
            $product_name ="$display_name ($product_name)" if ($display_name);
            $msg = "$product_name  usage : $result % ($used_license/$license_unit)" ;
            if ((defined($o_warning) || defined($o_critical))) {
                $np->set_thresholds(warning => $o_warning, critical => $o_critical);
                $status = $np->check_threshold($result);
                push( @criticals, "License usage is out of range $msg") if ($status==2);
                push( @warnings, "License usage is out of range $msg") if ($status==1);
                push (@ok,$msg) if ($status==0);
            } else {
                push (@ok,$msg);
            }            
        }
    } else {
        push(@licenses_name,$product_name);
    }
    $i++;
} while (exists $licences_list->{'value'}->[$i]);

if ($license_founded == 0){
    $msg = "license  " . $o_license_name . " not found  available license(s) is(are) : " . join(", ", @licenses_name);
    $np->plugin_exit('UNKNOWN',$msg);
}
$np->plugin_exit('CRITICAL', join(', ', @criticals)) if (scalar @criticals > 0);
$np->plugin_exit('WARNING', join(', ', @warnings)) if (scalar @warnings > 0);
$np->plugin_exit('UNKNOWN', join(', ', @unknown)) if (scalar @unknown > 0);
$np->plugin_exit('OK', join(', ', @ok));
