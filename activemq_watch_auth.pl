#!/usr/bin/perl -w

# Nagios plugin to check the current messages waiting in the ActiveMQ queue.
# Author: Maxim Janssens 
# Customized :Swarnim Ranjitkar
# Company: Synquad BV
# Website: http://www.synquad.nl
# Email: maxim@synquad.nl

#04/17/15 Veera - 	Made changes to store the prior values of size, how many times size has increased if the size has been growing and
#					whether alert was sent or not in the control file for comparison when the script runs next time.
 
#Usage: activemq_watch_auth control-file-name -w <warninglevel> -c <criticallevel> (-q <queue>) or -t <topic>) -n <numberoftimessizeshouldincreasebeforealert>
#		control-file=name to store the prior values.

#	sample record stored in the control file
#	Queue=ITS-EDS-Job howManyTimesMsgSizeIncreased=0 msgSize=0 sendAlert=N 

use strict;
use feature "switch";
use LWP;
use File::Basename;
no warnings 'experimental::smartmatch';


    my $to = 'veeraragavan.gopalakrishnan@ucsf.edu';
    my $subject;

	
	#my $page = get "http://$address:$port/admin/xml/queues.jsp" or die "Cannot get XML file: $!\n";;
	my (%args, %queues);
	my ($in_rec, $in_cnt, $field, $role, @ctl_recs, @ctl_out_recs);
	my %error=('ok'=>0,'warning'=>1,'critical'=>2,'unknown'=>3);
	my $printtype = "screen";
	my ($warninglevel, $criticallevel, $tmp, $evalcount, $queueselect, $queuevalue, $monitorType, $alertinterval);
	my $switch="";
	my $key = my $value = my $i = my $k = 0;
	my $exitcode = "unknown";
	my $monitorQueueFlag = my $monitorTopicFlag = 'N';
	my $statuspage;
	my @inputQueuesTopics;
	my $ctl_filename;
	
	if($ARGV[0] =~ /^\-/){
		$ctl_filename = basename($0,".pl").".ctl";
	}
	else{
		$ctl_filename = $ARGV[0];
	}
		
	for(my $m = 0; $m <= $#ARGV; $m++){
		if($ARGV[$m] =~ /^\-/){
			if($ARGV[$m] eq "-w"||"-c"||"-q" || "-o" || "-t" || "-n"){ 
				$switch = $ARGV[$m]; 
				$args{$switch} = (); 
				if($switch eq "-q"){ 
					$k = 1; 
					$monitorQueueFlag = 'Y';
					$monitorType = "Queue";
					$statuspage = "/admin/xml/queues.jsp";
				}
				if($switch eq "-t"){ 
#					$k = 1; 
					$monitorTopicFlag = 'Y';
					$monitorType = "Topic";
 					$statuspage="/admin/xml/topics.jsp";
				}
				if($switch eq "-o"){ $k = 2; }
	 		} else { &help; }
		} else {
			if($switch eq "-q"){ 
				$args{$switch} = $ARGV[$m];
			} 
			elsif($switch eq "-n"){ 
				$args{$switch} = $ARGV[$m];
			} 
			
			elsif($switch eq "-o"){ 
				$args{$switch} = $ARGV[$m]; 
			}
			elsif($switch eq "-t"){ 
				$args{$switch} = $ARGV[$m]; 
			}
			elsif($ARGV[$m] =~ /[0-9]{1,5}/){ 
				$args{$switch} = $ARGV[$m]; 
			} else { &help; }
		}
	}
	
	if($monitorQueueFlag eq 'Y' && $monitorTopicFlag eq 'Y') {
		print "Both -q and -t switches exist. Use either -q to monitor queue or -t to monitor topic.\n";
		&help;
	}
	
	if($monitorQueueFlag eq 'N' && $monitorTopicFlag eq 'N') {
		print "There is no -q or -t switch. Use either -q to monitor queue or -t to monitor topic.\n";
		&help;
	}
	# main();
	
	$warninglevel = $args{"-w"};
	$criticallevel = $args{"-c"};
	$alertinterval = $args{"-n"};
	
	#if($k == 1) { $queueselect = $args{"-q"}; }
	if($monitorQueueFlag eq 'Y'){@inputQueuesTopics = split ',',$args{"-q"};}
	if($monitorTopicFlag eq 'Y'){@inputQueuesTopics = split ',',$args{"-t"};}	
	if($k == 2) { $printtype = $args{"-o"}; }

	my $server1 = 'somvs108.som.ucsf.edu';
	my $server2 = 'somvs135.som.ucsf.edu';
    #my $server1 = 'localhost';
	#my $server2 = 'localhost';
	my $returnpageReq =  &request($server1, '8161', $statuspage);


	if (!$returnpageReq->is_success()){
		$returnpageReq = &request($server2, '8161', $statuspage);
	}

	if (!$returnpageReq->is_success()){
	 &printorsendmail ($printtype, "CRITICAL - activemq $monitorType", "CRITICAL - Can not access the page $statuspage on " . $server1 . " or " . $server2  );
	exit;
	
	}
		my $page = $returnpageReq->content;
	&readctlfile;	
	&getinfo;
#	if($k == 1){
	if($monitorQueueFlag eq 'Y' || $monitorTopicFlag eq 'Y'){
		foreach $queueselect (@inputQueuesTopics){
			$queuevalue = '';
			foreach my $str (keys %queues){
		
				if($queueselect eq $str){ $queuevalue = $queues{$queueselect}; last; }
				else { next; }
				}
		
			if($queuevalue eq ''){ 
				$exitcode = "unknown";
				&printorsendmail ($printtype, "CRITICAL activemq $monitorType not found ", "$monitorType $queueselect is not found \n");
				exit $error{"$exitcode"};
			} 
			else { &checkstatus($queuevalue,$queueselect); }
		}
	}else {
		while(($key, $value) = each(%queues)){ &checkstatus($value,$key); }
	}
	
	&writectlfile;
	
exit $error{"$exitcode"};

# Subroutines

sub readctlfile {
	if (-e $ctl_filename){
		open(FH, '<', $ctl_filename); 
		while (<FH>) {
    		$in_rec = {};
    		for $field ( split ) {
        		($key, $value) = split /=/, $field;
        		$in_rec->{$key} = $value;
    		}
    		push @ctl_recs, $in_rec;
		}
		close FH;
	}
}

sub writectlfile {
	open(FH, '>', $ctl_filename) || die "cannot open $ctl_filename file";	
	for $i ( 0 .. $#ctl_out_recs ) {
  		for $role ( sort keys %{ $ctl_out_recs[$i] } ) {
        		print FH "$role=$ctl_out_recs[$i]{$role} ";
   		}
   		print FH "\n";
	}
	close FH;
}

sub getinfo {
	my @lines = split ' ', $page;
	foreach my $line (@lines){
		   
        	if($line =~ /name/i || $line =~ /size/i){
                	$line =~ s/^name="//g;
                	$line =~ s/^size="//g;
                	$line =~ s/"(>)?$//g;
                	if($i == 1){
                        	$queues{$tmp} = $line;
                        	$i = 0;
                	}
                	else{
                        	$tmp = $line;
                        	$i++;
                	}
        	}
	}
}

sub checkstatus {	
	my $val=shift;
	my $key=shift;
	my $sendAlertEmail = checkctl($val, $key);
	if ($sendAlertEmail eq 'Y'){
		given($val){
			when ( $val <= $warninglevel ) { print "OK - $monitorType $key holding: $val msgs \n"; $exitcode = "ok" }
			when ( $val > $warninglevel && $val <= $criticallevel )	{ &printorsendmail ($printtype, "WARNING - activemq $monitorType", "WARNING - $monitorType $key holding: $val msgs \n"); $exitcode = "warning" }
			when ( $val > $criticallevel ) { &printorsendmail ($printtype, "CRITICAL activemq $monitorType ", "CRITICAL - $monitorType $key holding: $val msgs \n"); $exitcode = "critical"}
			default { &help; }
		}
	}
}

#Check the prior message size in the control file agains the current message size to decide whether to send an email or not
#Also compare the alertinterval value passed in the input parameter against the howManyTimesMsgSizeIncreased value in the control file.
#If howManyTimesMsgSizeIncreased >= alertinterval and sendAlert = 'N' then send a alert email and set sendAlert = 'Y' otherwise increment howManyTimesMsgSizeIncreased by 1 if current message size > prior message size.
#if current message size < prior message size then reset howManyTimesMsgSizeIncreased to zero and set sendAlert = 'N'. 

sub checkctl {
	my $currentMsgSize=shift;
	my $resourceName=shift;
	my $resourceFound = 'N';
	my $sendAlertEmail = 'N';
	for $i ( 0 .. $#ctl_recs ){
    	if (exists($ctl_recs[$i]{$monitorType}) && $ctl_recs[$i]{$monitorType} eq $resourceName){
    		$resourceFound = 'Y';
    		if ($currentMsgSize > $ctl_recs[$i]{"msgSize"}){
    			$ctl_recs[$i]{"howManyTimesMsgSizeIncreased"}++;
    			if ($ctl_recs[$i]{"howManyTimesMsgSizeIncreased"} >= $alertinterval){
    				if ($ctl_recs[$i]{"sendAlert"} eq 'N'){
    					$ctl_recs[$i]{"sendAlert"} = 'Y';
    					$sendAlertEmail = 'Y';
    				}
    			}	
    		}
    		elsif ($currentMsgSize > 0 && $currentMsgSize == $ctl_recs[$i]{"msgSize"}){
    			if ($ctl_recs[$i]{"sendAlert"} eq 'N'){
    				$ctl_recs[$i]{"sendAlert"} = 'Y';
    				$sendAlertEmail = 'Y';
    			}
    		}
    		else{
    			$ctl_recs[$i]{"howManyTimesMsgSizeIncreased"}=0;
    			$ctl_recs[$i]{"sendAlert"} = 'N';
    		}
    		$ctl_recs[$i]{"msgSize"} = $currentMsgSize;
    		push @ctl_out_recs, $ctl_recs[$i];
    	}		
	}
	if ($resourceFound eq 'N'){
		$in_rec = {};
		$in_rec->{$monitorType} = $resourceName;
		$in_rec->{"msgSize"} = $currentMsgSize;
		$in_rec->{"howManyTimesMsgSizeIncreased"} = 0;
		$in_rec->{"sendAlert"} = "N";
		push @ctl_out_recs, $in_rec;
	}
	return $sendAlertEmail;
}

sub help {
	print "Usage: activemq_watch control-file -w <warninglevel> -c <criticallevel> (-q <queue>) or -t <topic>) -n <numberoftimessizeshouldincreasebeforealert>\n";
	$exitcode = "unknown";
	exit $error{"$exitcode"};
}


sub request {
	my $address = shift;
	my $port = shift;
	my $statuslink = shift;

	my $browser = LWP::UserAgent->new;
 	my $pageres;

		$browser->agent('ReportsBot/1.01');
		
		$browser->credentials(
		  $address.':'.$port,
		  'ActiveMQRealm',
		  'admin' => 'admin'
		);
	
	
		 $pageres = $browser->get(
#		   'http://'.$address.':'.$port.'/admin/xml/queues.jsp'
		   'http://'.$address.':'.$port.$statuslink
			);
	
	
	return $pageres;
	
}

sub printorsendmail{
	my $printtype = shift;
	my $subject = shift;
	my $message = shift;
	if ($printtype eq "mail" ){
	 	open(my $MAIL, "|/usr/sbin/sendmail -t");
 
		# Email Header
		print $MAIL "To: $to\n";
		print $MAIL "Subject: $subject\n\n";
		# Email Body
		print $MAIL $message . $server1 . " " . $server2;
		
		close($MAIL);
		print "Email Sent Successfully\n";
	} else {
	  print $subject . " " . $message;
	}
}
