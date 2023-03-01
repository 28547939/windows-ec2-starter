#!/usr/local/bin/perl

use strict;
use warnings;
use Time::HiRes qw//;

use Data::Dumper qw/Dumper/;


use MIME::Base64 qw//;
use DateTime;
use DateTime::Format::ISO8601;
use Sort::Key::DateTime;
use POSIX qw//;


use Paws::EC2;

my $ec2 = Paws->service('EC2', region => $ENV{'REGION'} || 'us-east-1');

sub L (@) {
    printf "[%s]: %s\n",
        (POSIX::strftime '%Y-%m-%d_%H:%M:%S', localtime), 
        @_
    ;
}

L 'searching for images';

my $DescribeImagesResult = $ec2->DescribeImages(
  Filters         => [
    {
      Name   => 'name',
      Values => [ 'Windows_Server*' ]
    },

    {
      Name   => 'state',
      Values => [ 'available' ],        
    },

    {
      Name   => 'platform',
      Values => [ 'windows' ],        
    },
  ],                             
  Owners   => [ 'amazon'  ],           
);


 

my @images = Sort::Key::DateTime::dtkeysort { 
    DateTime::Format::ISO8601->parse_datetime($_->CreationDate) 
} @{ $DescribeImagesResult->Images };

L sprintf("found %d images", $#images);

print Dumper([(map { [ $_->ImageId, $_->Name, $_->Platform ] } @images[0..10]), '...']);

my $image = $images[0];

my $imageid = $image->ImageId;


my $launchid = sprintf('windows-%d', scalar Time::HiRes::gettimeofday());

L "launchid $launchid";
L "CreateSecurityGroup";


$ec2->CreateSecurityGroup(
    'GroupName'   => $launchid,
    'Description' => $launchid
);

L "AuthorizeSecurityGroupIngress";
$ec2->AuthorizeSecurityGroupIngress(
    'CidrIp'        => '0.0.0.0/0',
    'GroupName'     => $launchid,
    'IpProtocol'    => 'tcp',

    'FromPort'      => 3389,
    'ToPort'        => 3389,
);

$ec2->AuthorizeSecurityGroupIngress(
    'CidrIp'        => '0.0.0.0/0',
    'GroupName'     => $launchid,
    'IpProtocol'    => 'icmp',

    'FromPort'      => -1,
    'ToPort'        => -1,
);


L "RunInstances";
my $Reservation = $ec2->RunInstances(
	ImageId		    => $imageid,
    MinCount        => 1,
    MaxCount        => 1,
    InstanceType    => ($ENV{'INSTANCE_TYPE'} || 't3a.medium'),
    KeyName         => $ENV{'KEYNAME'},
    SecurityGroups  => [$launchid],
);

L 'RunInstances created Reservation';

my $inst = $Reservation->Instances->[0];
my $instid = $inst->InstanceId;

while (1) {
    sleep 2;
    $inst = $ec2->DescribeInstances(InstanceIds => [$instid])
        ->Reservations->[0]->Instances->[0];

    my $state = $inst->State->Name;

    last if $state eq 'running';
    L "waiting for instance; state is $state";
}

# InstanceRunning SystemStatusOk InstanceTerminated


L sprintf(
    'instance %s address %s', 
    $instid,
    $inst->NetworkInterfaces->[0]->Association->PublicIp
);

while (1) {

    # https://metacpan.org/pod/Paws::EC2::DescribeInstanceStatusResult ->InstanceStatuses
    # https://metacpan.org/pod/Paws::EC2::InstanceStatus ->SystemStatus
    # https://metacpan.org/pod/Paws::EC2::InstanceStatusSummary ->Status
    my $status = $ec2->DescribeInstanceStatus(
        InstanceIds => [ $instid ],
    )->InstanceStatuses->[0]->SystemStatus->Status;

    L sprintf('system status is %s', $status);

    last if $status eq 'ok';

    L 'waiting for system status OK';

    sleep 10;
}

my $starttime = localtime;


my $pw_enc;
while (1) {
    $pw_enc = $ec2->GetPasswordData(InstanceId  => $instid)->PasswordData;

    # Empty data will be returned until the password is generated
    last if defined $pw_enc && $pw_enc ne '';

    L 'waiting for password data';
    sleep 10;
}

L "encrypted password $pw_enc";

my $pw = qx{perl -MMIME::Base64 -e 'print MIME::Base64::decode_base64("$pw_enc")' | \
openssl rsautl -inkey $ENV{'KEYPATH'} -decrypt};

L sprintf('decrypted password %s IP %s', 
    $pw, 
    $inst->NetworkInterfaces->[0]->Association->PublicIp
);


sleep ($ENV{'RUN_TIME'} || 120);

eval {
    $ec2->TerminateInstances(InstanceIds => [$instid]);
};
if ($@) {
    print "error during TerminateInstances: $@";
}

L 'waiting for termination before deleting security group';


eval {
    while (1) {
        $inst = $ec2->DescribeInstances(InstanceIds => [$instid])
            ->Reservations->[0]->Instances->[0];

        my $state = $inst->State->Name;

        last if $state eq 'terminated';
        L "waiting for instance state; state is $state";
        sleep 10;
    }
};
if ($@) {
    print "error during DescribeInstances: $@";
}

$ec2->DeleteSecurityGroup(GroupName => $launchid);


L "deleted security group $launchid";


L 'done';
