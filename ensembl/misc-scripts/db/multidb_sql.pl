# apply given sql statement to all databases on a given host
# you can specify a name pattern for the database
# it displays results for select statements

# Author: Arne Stabenau
#  Date : 21.02.2003



use strict;
use DBI;

use Getopt::Long;

my ( $host, $user, $pass, $port, $expression, $dbpattern, $file, $result_only  );

GetOptions( "host=s", \$host,
	    "user=s", \$user,
	    "pass=s", \$pass,
	    "port=i", \$port,
	    "expr=s", \$expression,
	    "file=s", \$file,
	    "dbpattern|pattern=s", \$dbpattern,
            "result_only!", \$result_only,
	  );

if( !$host ) {
  usage();
}

my $dsn = "DBI:mysql:host=$host";
if( $port ) {
  $dsn .= ";port=$port";
}

my @expressions;

if( $file ) {
  local *FH;
  if( ! -r $file ) {
    die ( "File $file not readable" );
  }
  open( FH, "<$file" );
  
  my $exp;

  while( my $line = <FH> ) {
    if( $line =~ /;$/ ) {
      $line =~ s/;$//;
      $exp .= " ".$line;
      push( @expressions, $exp );
      $exp = "";
	
    } else {
      $exp .= " ".$line;
    }      
  }
  
  if( $exp ) {
    push( @expressions, $exp );
  }    
  
  close FH;
}

my $db = DBI->connect( $dsn, $user, $pass );

my @dbnames = map {$_->[0] } @{ $db->selectall_arrayref( "show databases" ) };

for my $dbname ( @dbnames ) {
  if( $dbpattern ) {
    if( $dbname !~ /$dbpattern/ ) {
      next;
    }
  }
  
   unless ($result_only) { 
    print "$dbname\n";
   }
  if(( ! $expression ) && ( !$file )) {
    next;
  }

  $db->do( "use $dbname" );
  if( $file ) {
    for my $sql ( @expressions ) {
      print "Do $sql\n";
      $db->do( $sql );
    }
  } elsif( $expression =~ /^\s*select/i ||
	   $expression =~ /^\s*show/i ||
	   $expression =~ /^\s*desc/i ) {
    my $res = $db->selectall_arrayref( $expression );
    my @results = map { join( " ", @$_ ) } @$res ;
    my $db_name_off = 0 ;
    for my $result ( @results ) {
     if($result_only){ 
      unless ($db_name_off){
        $db_name_off =1 ;
        print "==> $dbname :\n";
      }
     }
      print "    Result: ",$result,"\n";

    }
  } else {
    $db->do( $expression );
    print "  done.\n";
  }
}


sub usage {
  print STDERR <<EOF

             Usage: multidb_sql options
 Where options are: -host hostname 
                    -user username 
                    -pass password 
                    -port port_of_server optional
                    -dbpattern regular expression that the database name has to match
                    -expr sql statement you want to execute. 
                          if omitted, just print database names matching
                          if select, show or describe prints results
                    -file Apply sql in file to all databases. Doesnt print results.

EOF
;
  exit;
}

