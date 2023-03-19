#!/usr/bin/perl
use v5.36;
use warnings;
use strict;
use Getopt::Long;
use Data::Dump qw/dd/;
use JSON::XS;
use List::Util qw/first/;
use List::MoreUtils qw/nsort_by/;

my $dry_run;
my $server = "";

sub usage() {
	say STDERR "usage: $0 [--dry-run] --server <HOSTNAME> <HOSTNAME1>:<KEY1> ... <HOSTNAMEn>:<KEYn>";
	exit 1;
}

GetOptions("dry-run!" => \$dry_run, "server=s" => \$server) and $server or usage;

my $inputs = {map { split /:/, $_, -1 } @ARGV};

scalar(%$inputs) or $dry_run or usage;

sub find_ifaces {
	split /\s+/, (`iw dev | rg -or '\$1' "Interface (.+)"` or die "unable to assess ipv6 connectivity: $?")
}

sub find_addrs(@wifi_ifaces) {
	my %wifi_ifaces = map {$_, 1} @wifi_ifaces;
	my $addrs_raw_input = `ip -6 --json address show up scope global` or die "unable to assess ipv6 connectivity: $?";
	grep { $wifi_ifaces{$_->{ifname}} } @{decode_json($addrs_raw_input)}
}

sub find_router(@wifi_ifaces) {
	(
		first { exists $_->{router} && ! ( $_->{dst} =~ /^fe[89ab][0-9a-f]/ ) }
		map { @{decode_json(`ip -6 --json neighbor show dev $_`)}; }
		@wifi_ifaces
	)->{dst}
}

sub find_address(@wifi_ifaces) {
	(
		first { 1 }
		nsort_by { length $_->{local} }
		nsort_by { -$_->{prefixlen} }
		grep {
			my $addrinfo = $_;
			scalar keys %{$addrinfo}
			and $addrinfo->{scope} eq "global"
			and !$addrinfo->{temporary}
			and ($addrinfo->{mngtmpaddr} || $addrinfo->{noprefixroute})
			and !($addrinfo->{local} =~ /^f[cd]/)
			and $addrinfo->{valid_life_time} < ((1<<32) - 1)
		}
		map { @{$_->{addr_info}} }
		find_addrs(@wifi_ifaces)
	)->{local} or die "IPv6 misconfiguration"
}

sub bounce_connection {
	say STDERR "No internet connectivity";
	# TODO
}

my @wifi_ifaces = grep { system("iw $_ set power_save off &>/dev/null"); 1 } find_ifaces();

if (system("ping -c2 -w10 $server &>/dev/null") == 0) {
	my $preferred_address = find_address(@wifi_ifaces);
	say "$preferred_address" unless scalar %$inputs;
	while(my ($hostname, $key) = each %$inputs) {
		chomp (my $registered_address = `drill -Q AAAA $hostname`) or die "cannot determine current address: $?";
		my $no_op = ($preferred_address eq $registered_address);
		if ($no_op) {
			say "$hostname: $registered_address == $preferred_address";
		} elsif ($dry_run) {
			say "$hostname: $registered_address != $preferred_address";
		} else {
			system("curl", "-6fks", "https://$server/update/?h=$hostname&k=$key&aaaa=$preferred_address") == 0 or warn "failed to update $hostname";
		}
	}
} else {
	if (my $router = find_router(@wifi_ifaces)) {
		say STDERR "router is $router";
		if (system("ping -c2 -w10 ${router} &>/dev/null") == 0) {
			say STDERR "router is pingable - dyndns server must be down";
		} else {
			bounce_connection();
		}
	} else {
		say STDERR "No router in neighbors table";
		bounce_connection();
	}
}
