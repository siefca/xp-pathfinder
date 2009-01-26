#!/usr/bin/perl

# XP-Pathfinder, unused disks finder for XP matrix arrays
# by Pawel Wilk <pw@gnu.org> [GNU GPL Licensed]

# PURPOSE: This script is intended to be used for finding _unused_ devices
#          on the XP matrix array. It is helpful when you afraid of attaching
#          the devices which are already in use by other systems and your
#          main system is able to operate on these resoures too.
#
#          The script was tested on HP-UX(tm).
#          There is no warranty, use it at your own risk.

# USAGE:
#  0.) set up basic settings in this script's preamble (see Settings)
#  1.) execute 'xpinfo -d' command on hosts attached to your matrix array
#      saving the results in files
#  2.) execute 'xpinfo -d' on the host, on which you are going
#      to add some devices (and to create a volume group)
#  3.) transfer all report files to the one host
#  4.) put the concatenated results on the stdin of this script
#  5.) place the filename of the report from point 2.) as a first argument
#
# example:
#  cat xpinfo_host1 xpinfo_host2 | ./xp_pathfinder.pl xpinfo_from_host_to_use
#
#  (in most cases one of the filenames from the left side
#   will also be used as a mandatory parameter)
#

# Settings:
#
my $DISKS_COUNT_TO_USE=3;     # number of disks you would like to use
my $VOL_GROUP_NAME="vgnext";  # see man vgcreate for more details..
my $VOL_MINOR_PREFIX="0x0b00"; # see man vgcreate for more details..

my $ZIG_ZAG=1;                 # whether to switch physical linkage order
			       # for each one new added disk to increase speed
			       # (only useful on multipathed controllers)

#
#

my %devs;
my %freedevs;

# get the unused devices that we want to use from file (format: xpinfo -d)
#
open(PLIK, @ARGV[0]) or die("Cannot open file" . @ARGV[0]);
while (<PLIK>) {
    chop;
    my @l = split(/\,/);
    my ($path,$link,$id,$used) = ($l[0], $l[3], $l[4], $l[28]);

    $devs{$id}->{in_use} = 1 if ($used ne '---' && $used ne '');
    $devs{$id}->{paths}->{$link} = $path;
}
close(PLIK);

foreach my $id (keys %devs) {
    delete $devs{$id} if exists $devs{$id}->{in_use};
}

# collect the devices from standard input (format: xpinfo -d)
#
while (<STDIN>) {
    chop;
    my @l = split(/\,/);
    my ($id,$used) = ($l[4], $l[28]);

    next if not exists $devs{$id};
    $devs{$id}->{in_use} = $used if ($used ne '---' && $used ne '');
}

# remove unwanted devices
#
my $dct = $DISKS_COUNT_TO_USE;
foreach my $id (keys %devs) {
    my $line;

    next if exists $devs{$id}->{in_use};
    next if not exists $devs{$id}->{paths};
    last if !$dct--;
    $freedevs{$id} = $devs{$id};
}

my $max_vol = $DISKS_COUNT_TO_USE * 2;
$max_vol = 255 if ($max_vol > 255);
$max_vol = 32 if ($max_vol > 16 && $max_vol < 32);
$max_vol = 64 if ($max_vol > 32 && $max_vol < 64);
$max_vol = 128 if ($max_vol > 64 && $max_vol < 128);


print "XP-Pathfinder v1.0 by Pawel Wilk <pw\@gnu.org>\n\n";
print "Program was started with " . $DISKS_COUNT_TO_USE . " disks to dispose.\n";
print "Logical volume group is set to:\t\t\t" . $VOL_GROUP_NAME . "\n";
print "Minor device number prefix is set to:\t\t" . $VOL_MINOR_PREFIX . "\n";\
print "Controllers' paths zig-zag enabled:\t\t";
print "yes\n" if ($ZIG_ZAG);
print "no\n" if (!$ZIG_ZAG);
print "Calculated maximum physical volume count is:\t" . $max_vol . "\n\n";
print "Found unused physical devices:\n\n";

# find out free devices and print them
#
foreach my $id (keys %freedevs) {
    my $line;

    $line = " [" . $id . "] visible as ";
    foreach my $p ( sort keys %{$freedevs{$id}->{paths}} ) {
	$line .= $freedevs{$id}->{paths}->{$p};
	$line .= " (on $p), ";
    }
    $line =~ s/\,\s$//;
    print $line . "\n";
}

# generate helper scriptlets
#
print "\n\n---- scriptlets ----\n\n";

my $dupe = '';
my $create = '';
my $vgcreate = '';
my $initial = '';

foreach my $id (keys %freedevs) {
    foreach my $p ( sort keys %{$freedevs{$id}->{paths}} ) {
	$first = $freedevs{$id}->{paths}->{$p};
	$dupe .= "dd if=/dev/zero of=" . $first . " bs=1024 count=1024\n";
	$create .= "pvcreate -f " . $first . "\n";
	last;
    }
}

foreach my $id (keys %freedevs) {
    foreach my $p ( sort keys %{$freedevs{$id}->{paths}} ) {
	$initial .= $freedevs{$id}->{paths}->{$p} . " ";
    }
    delete $freedevs{$id};
    last;
}
$initial =~ s/\/rdsk/\/dsk/g;

my $vol_gr_dir = "/dev/" . $VOL_GROUP_NAME;
my $toextend = '';
my $switch = 0;
foreach my $id (keys %freedevs) {
    $toextend .= "vgextend " . $vol_gr_dir . " ";
    if (!$ZIG_ZAG || $switch) {
	$switch = 0;
	foreach my $p ( sort keys %{$freedevs{$id}->{paths}} ) {
	    $toextend .= $freedevs{$id}->{paths}->{$p} . " ";
	}
    } else {
	$switch = 1;
	foreach my $p ( reverse sort keys %{$freedevs{$id}->{paths}} ) {
	    $toextend .= $freedevs{$id}->{paths}->{$p} . " ";
	}
    }
    $toextend .= "\n";
}
$toextend =~ s/\/rdsk/\/dsk/g;

print "\n# clear headers:\n";
print $dupe;
print "\n# initialize physical devices:\n";
print $create;
print "\n# create volume group:\n";
print "mkdir " . $vol_gr_dir . "\n";
print "mknod " . $vol_gr_dir . "/group c 64 " . $VOL_MINOR_PREFIX . "00\n";
print "chmod o-rwx,g+r-wx " . $vol_gr_dir . "/group\n";
print "vgcreate -s 8 -p " . $max_vol . " " . $vol_gr_dir . " " . $initial . "\n";
print "\n# add disks to the volume group:\n";
print $toextend;
print "\n# create logical volume:\n";
print "\n# do it by hand: man lvcreate ;)\n";
print "\n";


print "\n\n---- end of scriptlets ----\n\n";

exit(0);
