#! /usr/bin/perl -w

use v5.10;
use utf8;                        # utf-8 source code
use strict;
use warnings;
use warnings qw(FATAL utf8);    # fatalize encoding glitches
use open qw( :encoding(UTF-8) :std );
use Encode::Locale qw(decode_argv);

use Getopt::Long qw(:config bundling pass_through);
use Pod::Usage;
use IPC::Open3;

use constant {
	VERSION => 1,
};
my %engines = ( httperf => "Httperf", siege => "Siege" );

# initialize options
my %opts = (
	verbose => 0,
	debug => 0,
	steps => 0,
	varying => "",
	engine => "",
);

# Read command-line options
GetOptions(
	\%opts,
	"man",
	"help|h",
	"verbose|v+",
	"debug|D+",
	# specific options
	"engine|e=s",
	"steps=i",
	"varying=s",
);
$opts{verbose} += 5 * $opts{debug};

# Print help thanks to Pod::Usage
pod2usage({-verbose => 2, -utf8 => 1, -noperldoc => 1}) if $opts{man};
pod2usage({-verbose => 0, -utf8 => 1, -noperldoc => 1}) if $opts{help};
if ($opts{steps} < 2) {
	pod2usage({-verbose => 0, -utf8 => 1, -noperldoc => 1,
			   -message => "--steps is required and must be greater than 1"});
}
$opts{engine} = lc($opts{engine});
if (not exists $engines{$opts{engine}}) {
	pod2usage({-verbose => 0, -utf8 => 1, -noperldoc => 1,
			   -message => "--engine is required and must be " . join('|', keys %engines)});
}

my @options_fixed = ();
my @option_varying = ();
my $option_name = "";
foreach (@ARGV) {
	next if $_ eq "--";
	my $option_name = '';
	my $start;
	my @s = split /\.\.\./;
	if (@s == 2 and $s[1] =~ /^\d+$/) {
		if (/^(--.+?=)(\d+)/ or /^(-[a-zA-Z])(\d+)/) {
			($option_name, $start) = ($1, $2);
			my $inc = int(($s[1] - $start) / ($opts{steps} - 1));
			foreach my $step (1 .. $opts{steps}) {
				push @option_varying, { value => $start, parameters => [$option_name . $start] };
				$start += $inc;
			}
		} elsif (/^-/) {
			$option_name = '';
			push @options_fixed, $_;
		} else {
			$option_name = pop @options_fixed;
			$start = $s[0];
			my $inc = int(($s[1] - $start) / ($opts{steps} - 1));
			foreach my $step (1 .. $opts{steps}) {
				push @option_varying, { value => $start, parameters => [$option_name, $start] };
				$start += $inc;
			}
		}
		if ($option_name and not $opts{varying}) {
			$opts{varying} = $option_name;
			$opts{varying} =~ s/^-+//;
			$opts{varying} =~ s/=$//;
		}
	} else {
		push @options_fixed, $_;
	}
}
if (not @option_varying) {
	die "Nothing to increase at each step. Missing a parameter that declares a range.\n";
}
if ($opts{verbose}) {
	print STDERR "Varying parameter:\n\t", join(' / ', map { join(" ", @{$_->{parameters}}); } @option_varying), "\n";
}

my $engine = "Bench::" . $engines{$opts{engine}};
my @columns = $engine->get_columns();
say join("\t", $opts{varying}, @columns); # header
foreach my $opt (@option_varying) {
	my $results = $engine->benchmark([ @{$opt->{parameters}}, @options_fixed ]);
	say join("\t", $opt->{value}, @$results{@columns});
}


#################################################################

package Bench::Common;

sub check_options {
	my ($options, $required) = @_;
	foreach my $req (@$required) {
		die "Missing httperf parameter '$req'\n" unless (grep { m/--$req(\b|=)/ } @$options);
	}
}

sub benchmark_filtered {
	my ($command, $options, $required_options) = @_;

    print STDERR "EXEC: $command ", join(" ", map { '"' . $_ . '"' } @$options), "\n" if ($opts{verbose});
	if ($required_options and @$required_options) {
		check_options($options, $required_options);
	}

	# TODO: try to use IPC::Run on Windows, list form pipes are UNIX specific
	# Siege outputs info on STDERR so `open ($o, "-|", @cmd)` won't work
	my $out;
	IPC::Open3::open3(my $in, $out, $out, ($command, @$options))
		or die "Cannot execute $command: $!\n";
	return $out;
}

#################################################################

package Bench::Httperf;

sub get_columns {
	return qw/requests replies connection_rate request_rate reply_rate_min reply_rate_avg reply_rate_max reply_rate_stddev reply_time net_io errors errors_percent/;
}

sub benchmark {
	my ($self, $options) = @_;

	my $run = Bench::Common::benchmark_filtered("httperf", $options, [qw/num-conns num-calls/]);
	return parse_output($run);
}

sub parse_output {
	my ($output) = @_;

	my %results = ();
	say STDERR "-"x60 if $opts{verbose} > 1;
    while (<$output>) {
		if (/^Total: .*requests (\d+) replies (\d+)/) {
			$results{requests} = $1;
			$results{replies} = $2;
		}
		if (/^Connection rate: (\d+\.\d)/) {
			$results{connection_rate} = $1;
		}
		if (/^Request rate: (\d+\.\d)/) {
			$results{request_rate} = $1;
		}
		if (/^Reply rate .*min (\d+\.\d) avg (\d+\.\d) max (\d+\.\d) stddev (\d+\.\d)/) {
			$results{reply_rate_min} = $1;
			$results{reply_rate_avg} = $2;
			$results{reply_rate_max} = $3;
			$results{reply_rate_stddev} = $4;
		}
		if (/^Reply time .* response (\d+\.\d)/) {
			$results{reply_time} = $1;
		}
		if (/^Net I\/O: (\d+\.\d)/) {
			$results{net_io} = $1;
		}
		if (/^Errors: total (\d+)/) {
			$results{errors} = $1;
		}
		print STDERR "HTTPERF: $_" if $opts{verbose} > 1;
    }
    close ($output);
	say STDERR "-"x60 if $opts{verbose} > 1;

    if (not exists $results{replies} or $results{replies} == 0) {
		print STDERR "Zero replies received, invalid benchmark.\n";
		$results{errors_percent} = 100;
    } else {
		$results{errors_percent} = int(100 * $results{errors} / $results{replies});
    }
    return \%results;
}

#################################################################

package Bench::Siege;

sub get_columns {
	return qw/Transactions Availability Elapsed_time Data_transferred Response_time Transaction_rate Throughput Concurrency Successful_transactions Failed_transactions Longest_transaction Shortest_transaction Errors_percent/;
}

sub benchmark {
	my ($self, $options) = @_;

	my $run = Bench::Common::benchmark_filtered("siege", $options);
	return parse_output($run);
}

sub parse_output {
	my ($output) = @_;

	my %results = ();
	say STDERR "-"x60 if $opts{verbose} > 1;
    while (<$output>) {
		if (m/^([A-Z][a-z ]+):\s+(\d+(?:\.\d+)?)\b/) {
			my ($k, $v) = ($1, $2);
			$k =~ y/ /_/;
			$results{$k} = $v;
		}
		print STDERR "SIEGE: $_" if $opts{verbose} > 1;
    }
    close ($output);
	say STDERR "-"x60 if $opts{verbose} > 1;

    if (not exists $results{Successful_transactions} or $results{Successful_transactions} == 0) {
		$results{Errors_percent} = 100;
    } else {
		$results{Errors_percent} = int(100 * $results{Failed_transactions} / ($results{Failed_transactions} + $results{Successful_transactions}));
    }
    return \%results;
}

#################################################################

__END__

=encoding utf8

=head1 NAME

bench-range.pl

=head1 SYNOPSIS

bench-range [options] --steps X --engine=[httperf|siege] [[--] I<engine-options>]

=head1 OPTIONS

=head2 BENCHMARK OPTIONS

=over 8

=item B<--engine=>httperf|siege

Name of the benchmark program to run. Required.

=item B<--option=from...to>, B<-o from...to>

The first run will use I<--option=from> and the last one I<--option=to>
(or a slightly inferior value if I<from - to> is not a multiple of I<steps>).

=item B<--steps=>

Number of successive benchmark runs.
Required. Must be greater than 1!

=item B<--varying=Title>

Title of the varying option, for the CSV report.
The name of the option will be used by default.

=back

=head2 GENERAL OPTIONS

=over 8

=item B<-h, --help>

Print a short help notice.

=item B<--man>

Print this man page.

=item B<-v, --verbose>

Increase verbosity.

=back

=head1 EXAMPLES

Send 1000 queries at 100, 200, 300 requests per second using I<httperf>,
and store the results in a CSV file:

./bench-range.pl --steps 3 --engine=httperf --server=localhost --uri=/ --num-conns=1000 --rate=100...300 > a.csv

Send 1000 queries (2 per connection) at 10 to 100 requests per second in 10 runs using I<httperf>,
store the results in a CSV file and the detailed logs in a separate file:

./bench-range.pl -vv --steps 10 --engine httperf -- --server=localhost --uri=/ --timeout 5 --hog --num-calls=2 --num-conns=500 --rate=10...100 > a.csv 2> a.log

Send queries for 10 seconds at 10 to 100 concurrency in 10 runs using I<siege>,
store the results in a CSV file and the detailed logs in a separate file:

./bench-range.pl -vv --steps 10 --engine siege -- --benchmark --time=10S --concurrent=10...100 http://localhost/ > a.csv 2> a.log

=cut

=cut
