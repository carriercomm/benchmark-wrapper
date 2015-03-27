#! /usr/bin/perl -w

# Copyright (C) 2015  François Gannaz <francois.gannaz@silecs.info>

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use v5.10;
use utf8;
use strict;
use warnings;
use warnings qw(FATAL utf8);    # fatalize encoding glitches
use open qw( :encoding(UTF-8) :std );
#use Encode::Locale qw(decode_argv); # Not installed by default

use Getopt::Long qw(:config bundling);
use Pod::Usage;
use File::Temp;
use File::Slurp;

use constant {
	VERSION => 1,
};

# initialize options
my %opts = (
	verbose => 0,
	plot => 1,
);

# Read command-line options
GetOptions(
	\%opts,
	"man",
	"help|h",
	"verbose|v+",
	"title|t=s",
	"columns|c=s",
	"outputfile|output-file|o=s",
	"gnuplotfile|gnuplot-file|g=s",
);

# Print help thanks to Pod::Usage
pod2usage({-verbose => 2, -utf8 => 1, -noperldoc => 1}) if $opts{man};
pod2usage({-verbose => 0, -utf8 => 1, -noperldoc => 1}) if $opts{help};

my @source_files = grep {/^[^-]/} @ARGV;
if (not @source_files) {
	pod2usage({-verbose => 0, -utf8 => 1, -noperldoc => 1, -message => "Please give a source file name.\n"});
}
foreach my $source_file (@source_files) {
	die "Source file not found or not readable.\n" unless (-f -r $source_file);
}

if (not defined $opts{title}) {
	$opts{title} = $source_files[0];
}

my @data = File::Slurp::read_file($source_files[0], chomp => 1);
my @header = split /\t/, shift(@data);

my @columns;
if ($opts{columns}) {
	@columns = split /[,:]/, $opts{columns};
} else {
	@columns = ask_columns(\@header, \@data);
}
my @plots = build_plot_commands(\@columns, \@header, \@source_files);

if (defined $opts{outputfile}) {
	if ($opts{outputfile} =~ /\.(gnu)?plot$/) {
		$opts{gnuplotfile} = $opts{outputfile};
		$opts{plot} = 0;
	}
} else {
	$opts{outputfile} = $source_files[0];
	$opts{outputfile} =~ s/\.[a-z]{2,5}$//;
	if (@columns == 1) {
		$opts{outputfile} .= "_" . $header[$columns[0]];
	}
	$opts{outputfile} .= ".png";
}

my $plot_fh;
if (defined $opts{gnuplotfile}) {
	open $plot_fh, ">", $opts{gnuplotfile}
		or die "$!\n";
} else {
	($plot_fh, $opts{gnuplotfile}) = File::Temp::tempfile();
}

if ($opts{outputfile} =~ m/\.([a-z]{2,5})$/) {
	say $plot_fh "set terminal " . $1;
} else {
	say $plot_fh "set terminal png";
}
say $plot_fh "set key outside below";
say $plot_fh "set key box";
say $plot_fh "set grid";
say $plot_fh "set yrange [0:]";
say $plot_fh "set style data linespoints";
say $plot_fh "set title '${opts{title}}'" if $opts{title};
say $plot_fh "set output '${opts{outputfile}}'\n";
say $plot_fh "plot " . join(', ', @plots);

if ($opts{plot}) {
	system("gnuplot", $opts{gnuplotfile});
}


#################################################################

sub ask_columns {
	my ($head, $data) = @_;
	my $minmax = compute_minmax($data);
	my $pos = 0;
	my @header = @$head;
	foreach (@header[1 .. $#header]) {
		printf "Col %2d: %-30s  [%7s, %7s]\n", $pos + 1, $_, @{$minmax->[$pos+1]};
		$pos++;
	}
	print "Which columns? e.g. 3,4,5.  ";
	my $in = <STDIN>;
	chomp($in);
	my @columns = split /\s*[, ]\s*/, $in;
	return @columns;
}

sub build_plot_commands {
	my ($columns, $header, $files) = @_;
	my @named_columns = grep {$_}
		map {
			if ($_ > 0) {
				my $title = $header->[$_];
				sprintf("'%%s' using 1:%d title '%%s%s' ", $_+1, $title);
			}
		} @$columns;
	my @total = ();
	foreach my $source_file (@$files) {
		my $prefix = (@$files > 0 ? $source_file . " " : "");
		$prefix =~ s/\.[a-z]{2,5} $/ /;
		$prefix =~ s#^.+/##;
		my @plot_for_file = map { sprintf($_, $source_file, $prefix) } @named_columns;
		push @total, join(', ', @plot_for_file);
	}
	return @total;
}

sub compute_minmax {
	my ($data) = @_;
	my @minmax = ();
	foreach my $line (@$data) {
		if (@minmax) {
			my $i = 0;
			foreach (split(/\t/, $line)) {
				if ($_ < $minmax[$i][0]) {
					$minmax[$i][0] = $_;
				} elsif ($_ > $minmax[$i][1]) {
					$minmax[$i][1] = $_;
				}
				$i++;
			}
		} else {
			@minmax = map { [$_,$_] } split(/\t/, $line);
		}
	}
	return \@minmax;
}


__END__

=encoding utf8

=head1 NAME

bench-graph.pl

=head1 SYNOPSIS

bench-graph.pl [options] source.tsv [source2.csv ...]

Produce a graph, using Gnuplot, from the tab-separated data files.

=head1 OPTIONS

=over 8

=item B<-c, --columns>

Columns to graph. List of values from 1, separated by ",".
Column 0 is the absciss.

=item B<-h, --help>

Print a short help notice.

=item B<--man>

Print this man page.

=item B<-o, --output-file>

Name of the file where the graph will be written.
The extension must be a format that Gnuplots admits (png, pdf, ps, etc)
or ".gnuplot" (in which case the gnuplot command won't be called).
Defaults to the source file name, with the extension replaced by ".png".

=item B<-t, --title>

Graph title. Defaults to the source file name.

=item B<-v, --verbose>

Increase verbosity.

=back

=head1 Examples

Select the columns interactively and produce a "bench1.png" file:

    bench-graph.pl bench1.csv

Produce a "bench1.png" file with the first column as absciss
and the next five columns of the benchmarks ordinates.

    bench-graph.pl bench1.tsv -c 1,2,3,4,5

Produce a "bench1_errors.png" file with the column 10 (supposing the column title is "errors"), and a graph title set to "Host1 Errors".

    bench-graph.pl --title="Host1 Errors" bench1.tsv -c 10

Produce a comparison graph in "bench_errors.png" file with the column 10 of each source file.

    bench-graph.pl -o "bench_errors.png" -t "Errors" bench*.csv -c 10

Produce a PDF graph.

    bench-graph.pl -o graph.pdf bench.tsv -c 8

=cut
