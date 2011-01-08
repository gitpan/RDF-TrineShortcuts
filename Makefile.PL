use strict;
use warnings;

use inc::Module::Install;

my $dist = 'RDF-TrineShortcuts';
my $fn   = "lib/$dist.pm"; $fn =~ s#-#/#g;

name                $dist;
perl_version_from   $fn;
version_from        $fn;
abstract_from       $fn;
readme_from         $fn;
author              'Toby Inkster <tobyink@cpan.org>';
license             'perl';

requires            'Exporter'           => 0;
requires            'File::Slurp'        => 0;
requires            'Getopt::Long'       => 0;
requires            'LWP::Simple'        => 0;
requires            'Pod::Usage'         => 0;
requires            'RDF::RDFa::Parser'  => '1.093';
requires            'RDF::Trine'         => '0.130';
requires            'RDF::Query'         => '2.903';
requires            'RDF::Query::Client' => '0.03';
requires            'URI'                => '1.30';
requires            'URI::file'          => 0;
requires            'YAML'               => 0;
recommends          'HTTP::Link::Parser' => '0.04';
recommends          'RDF::RDFa::Generator' => '0.03';
recommends          'RDF::TriN3'         => '0.126';
recommends          'Spreadsheet::Write' => '0.100';
recommends          'XML::Atom::OWL'     => '0.02';
recommends          'XRD::Parser'        => '0.05';
test_requires       'Module::Signature'  => '0.66';
test_requires       'Test::More'         => '0.61';

install_script 'toquet';
install_script 'trapper';
install_script 'trist';

resources(
	'homepage'   => "http://search.cpan.org/dist/$dist/",
	'repository' => "http://goddamn.co.uk/viewvc/perlmods/$dist/",
	'bugtracker' => "http://rt.cpan.org/Dist/Display.html?Queue=$dist",
	);

keywords 'Semantic Web', 'RDF', 'Hack';

write_doap_changes;
write_doap_changes_xml;

include 'Test::Signature';
auto_install;
WriteAll(
	'meta' => 1,
	'sign' => 1,
	);
