#! /usr/bin/perl -w

use v5.10;
use utf8;
use strict;
use warnings;
use warnings qw(FATAL utf8);    # fatalize encoding glitches
use open qw( :encoding(UTF-8) :std );
use Encode::Locale qw(decode_argv);

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
use Pod::Usage;
pod2usage({-verbose => 2, -utf8 => 1, -noperldoc => 1}) if $opts{man};
pod2usage({-verbose => 0, -utf8 => 1, -noperldoc => 1}) if $opts{help};

my $source_file = shift @ARGV;
if (not $source_file) {
	print "Please give a source file name.\n\n";
	pod2usage({-verbose => 0, -utf8 => 1, -noperldoc => 1}) if $opts{help};
}
die "Source file not found or not readable.\n" unless (-f -r $source_file);

if (not defined $opts{title}) {
	$opts{title} = $source_file;
}

my $plot_fh;
if (defined $opts{gnuplotfile}) {
	open $plot_fh, ">", $opts{gnuplotfile}
		or die "$!\n";
} else {
	($plot_fh, $opts{gnuplotfile}) = File::Temp::tempfile();
}

my $first = (File::Slurp::read_file($source_file))[0];
chomp $first;
my @header = split /\t/, $first;

my @columns = (2 .. 10);
if ($opts{columns}) {
	@columns = split /[,:]/, $opts{columns};
}
my @named_columns = grep {$_} map { if ($_ > 1) { my $title = $header[$_-1]; "'$source_file' using 1:$_ title '$title' ";}  } @columns;

if (not defined $opts{outputfile}) {
	$opts{outputfile} = $source_file;
	$opts{outputfile} =~ s/\.[a-z]{2,5}$//;
	if (@columns == 1) {
		$opts{outputfile} .= "_" . $header[$columns[0]-1];
	}
	$opts{outputfile} .= ".png";
}

if ($opts{outputfile} =~ m/\.([a-z]{2,5})$/) {
	say $plot_fh "set terminal " . $1;
} else {
	say $plot_fh "set terminal png";
}
say $plot_fh "set key outside below";
say $plot_fh "set key box";
say $plot_fh "set grid";
say $plot_fh "set style data linespoints";
say $plot_fh "set title '${opts{title}}'" if $opts{title};
say $plot_fh "set output '${opts{outputfile}}'\n";
say $plot_fh "plot " . join(', ', @named_columns);

system("gnuplot", $opts{gnuplotfile});


#################################################################


__END__

=encoding utf8

=head1 NAME

bench-graph.pl

=head1 SYNOPSIS

bench-graph.pl [options] source.tsv

=head1 OPTIONS

=over 8

=item B<-c, --columns>

Columns to graph. List of values from 2 to 10, separated by ",".

=item B<-h, --help>

Print a short help notice.

=item B<--man>

Print this man page.

=item B<-o, --output-file>

Name of the file where the graph will be written.
Defaults to the source file name, with the extension replaced by ".png".

=item B<-t, --title>

Graph title. Defaults to the source file name.

=item B<-v, --verbose>

Increase verbosity.

=back

=head1 Examples

Produce a "bench1.png" file with the first column as absciss
and the next five columns of the benchmarkas ordinates.

    bench2graph.pl bench1.tsv -c 2,3,4,5,6

Produce a "bench1_errors_host1.png" file with the last column (errors), and a graph title set to "Host1 Errors".

    bench2graph.pl --title="Host1 Errors" bench1.tsv -c 10

Produce a PDF graph.

    bench2graph.pl -o graph.pdf bench.tsv -c 8

=cut
