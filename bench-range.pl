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

use constant {
	VERSION => 1,
};

# initialize options
my %opts = (
	verbose => 0,
	debug => 0,
	steps => 0,
	varying => "",
);

# Read command-line options
GetOptions(
	\%opts,
	"man",
	"help|h",
	"verbose|v+",
	"debug|D+",
	# specific options
	"steps=i",
	"varying=s",
);
$opts{verbose} += 5 * $opts{debug};

# Print help thanks to Pod::Usage
pod2usage({-verbose => 2, -utf8 => 1, -noperldoc => 1}) if $opts{man};
pod2usage({-verbose => 0, -utf8 => 1, -noperldoc => 1}) if $opts{help};
if ($opts{steps} < 2) {
	pod2usage({-verbose => 0, -utf8 => 1, -noperldoc => 1, -message => "--steps is required and must be greater than 1"});
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

my @columns = qw/requests replies connection_rate request_rate reply_rate_min reply_rate_avg reply_rate_max reply_rate_stddev reply_time net_io errors errors_percent/;
say join("\t", $opts{varying}, @columns); # header
foreach my $opt (@option_varying) {
	my $results = Bench::Httperf::benchmark([ @{$opt->{parameters}}, @options_fixed ]);
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

    print STDERR "EXEC: $command", join(" ", map { '"' . $_ . '"' } @$options), "\n" if ($opts{verbose});
	if ($required_options and @$required_options) {
		check_options($options, $required_options);
	}

	# TODO: try to use IPC::Run on Windows, list form pipes are UNIX specific
    open (my $run, "-|", ($command, @$options))
		or die "Cannot execute $command: $!\n";
	return $run;
}

#################################################################

package Bench::Httperf;

sub benchmark {
	my ($options) = @_;

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
		print STDERR $_ if $opts{verbose} > 1;
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

__END__

=encoding utf8

=head1 NAME

bench-range.pl

=head1 SYNOPSIS

bench-range [options] --steps X [[--] I<httperf-options>]

=head1 OPTIONS

=head2 BENCHMARK OPTIONS

=over 8

=item B<--option=from...to>, B<-o from...to>

The first run will use I<--option=from> and the last one I<--option=to>
(or a slightly inferior value if I<from - to> is not a multiple of I<steps>).

=item B<--steps=>

Number of successive benchmark runs.
Must be greater than 1!

=item B<--varying=Title>

Title of the varying option, for the CSV report.

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

Send 1000 queries at 100, 200, 300 requests per second,
and store the results in a CSV file:

./bench-range.pl --steps 3 --server=localhost --uri=/ --num-conns=1000 --rate=100...300 > a.csv

Send 1000 queries (2 per connection) at 10 to 100 requests per second in 10 runs,
store the results in a CSV file and the detailed logs in a separate file:

./bench-range.pl -vv --steps 10 -- --server=localhost --uri=/ --timeout 5 --hog --num-calls=2 --num-conns=500 --rate=10...100 > a.csv 2> a.log

=cut

=cut
