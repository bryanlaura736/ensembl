#!/usr/local/bin/perl -w

# $Id$
#
# Author: Andreas Kahari <andreas.kahari@ebi.ac.uk>
#
# This is a  wrapper around Richard Durbin's
# pmatch code (fast protein matcher).

use strict;
use warnings;

use Data::Dumper;	# For debugging output

use Getopt::Std;

sub overlap
{
	# Returns the length of the overlap of the two ranges
	# passed as argument.  A range is a two element array.

	my $first  = shift;
	my $second = shift;

	# Order them so that $first starts first.
	if ($first->[0] > $second->[0]) {
		($first, $second) = ($second, $first);
	}

	# No overlap
	return 0 if ($first->[1] < $second->[0]);

	# Partial overlap
	return ($first->[1] - $second->[0] + 1) if ($first->[1] < $second->[1]);

	# Full overlap
	return ($first->[1] - $first->[0] + 1);
}

my $pmatch_cmd	= '/nfs/disk5/ms2/bin/pmatch';
my $pmatch_opt	= '-T 14';
my $pmatch_out	= '/tmp/pmatch_out.' . $$;	# Will be unlinked

my $datadir	= '/acari/work4/mongin/final_build/release_mapping/Primary';
my $target	= $datadir . '/final.fa';
my $query	= $datadir . '/sptr_ano_gambiae_19_11_02_formated.fa';

# Set defaults
my %opts = (
	'b'	=> '0',
	'c'	=> $pmatch_cmd,
	'q'	=> $query,
	't'	=> $target );

if (!getopts('bc:q:t:', \%opts)) {
	print(STDERR "Usage: $0 [-b] [-c path] [-q path] [-t path]\n\n");
	print(STDERR "-b\tDisplay header\n\n");
	print(STDERR "-c path\tUse the pmatch executable located " .
		"at 'path' rather than at\n");
	print(STDERR "\t$pmatch_cmd\n\n");
	print(STDERR "-q path\tTake query FastA file from 'path' rather " .
		"than from\n");
	print(STDERR "\t$query\n\n");
	print(STDERR "-t path\tTake target FastA file from 'path' rather " .
		"than from\n");
	print(STDERR "\t$target\n\n");
	die;
}

# Override defaults
$pmatch_cmd	= $opts{'c'};
$query		= $opts{'q'};
$target		= $opts{'t'};

if (system("$pmatch_cmd $pmatch_opt $target $query >$pmatch_out") != 0) {
	# Failed to run pmatch command
	die($!);
}

open(PMATCH, $pmatch_out) or die($!);

my %hits;

# Populate the %hits hash.
while (defined(my $line = <PMATCH>)) {
	my ($length,
		$qid, $qstart, $qend, $qperc, $qlen,
		$tid, $tstart, $tend, $tperc, $tlen) = split(/\s+/, $line);

	if (!exists($hits{$qid}{$tid})) {
		$hits{$qid}{$tid} = {
			QLEN	=> $qlen,
			TLEN 	=> $tlen,
			HITS	=> [ ]
		};
	}

	push(@{ $hits{$qid}{$tid}{HITS} }, {
		QSTART	=> $qstart,
		QEND	=> $qend,
		TSTART	=> $tstart,
		TEND	=> $tend });
}

close(PMATCH);

unlink($pmatch_out);	# Get rid of pmatch output file

foreach my $query (values(%hits)) {
	foreach my $target (values(%{ $query })) {

		foreach my $c ('Q', 'T') {

			my $overlap = 0;	# Total query overlap length
			my $totlen = 0;		# Total hit length

			my $gaps = 0;	# Number of gaps in the query
					# Are these interesting?

			my @pair;
			foreach my $hit (
				sort { $a->{$c . 'START'} <=>
				       $b->{$c . 'START'} }
				@{ $target->{HITS} }) {

				$totlen += $hit->{$c . 'END'} -
					   $hit->{$c . 'START'} + 1;

				shift(@pair) if (scalar(@pair) == 2);
				push(@pair, $hit);
				next if (scalar(@pair) != 2);

				my $o = overlap([$pair[0]{$c . 'START'},
						 $pair[0]{$c . 'END'}],
						[$pair[1]{$c . 'START'},
						 $pair[1]{$c . 'END'}]);
				$overlap += $o;

				++$gaps if ($o == 0); # ($o <= 1  ???)
			}

			# Calculate the query and target identities
			$target->{$c . 'IDENT'} =
				100*($totlen - $overlap)/$target->{$c . 'LEN'};
			$target->{$c . 'GAPS'}  = $gaps;
		}
	}
}

if ($opts{'b'}) {
	printf("%8s%8s%8s%8s%8s%8s%8s%8s\n",
		'QID', 'QLEN', 'QIDENT', 'QGAPS',
		'TID', 'TLEN', 'TIDENT', 'TGAPS');
}

while (my ($qid, $query) = each %hits) {
	while (my ($tid, $target)  = each %{ $query }) {
		printf("%8s%8d%8.3f%8d%8s%8d%8.3f%8d\n",
			$qid, $target->{QLEN},
			$target->{QIDENT}, $target->{QGAPS},
			$tid, $target->{TLEN},
			$target->{TIDENT}, $target->{TGAPS});
	}
}

#print Dumper(\%hits);	# Produce debugging output
