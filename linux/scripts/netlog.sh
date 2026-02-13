#!/bin/sh

# usage: netlog.sh
#        netlog.sh info <dir> [num]

OUTPUT_DIR="$(mktemp -d /tmp/netlog.XXXXX)"

dns() {
	sudo tcpdump -i any -n -T domain port 53 -l 2>/dev/null |
		grep -o --line-buffered '\(A\|AAAA\)? .*\. ' |
		sed -u 's/^A\+? \|\. $//g' |
		tee -a "$OUTPUT_DIR/dns"
}

tcp_udp() {
	sudo tcpdump -nq -i any -l '(tcp or udp)' 2>/dev/null |
		perl -lane 'BEGIN{$|=1}; $F[0]=~s/\..*//; ($sh,$sp)=$F[4]=~/^(.*)\.(.*)$/; ($dh,$dp)=$F[6]=~/^(.*)\.(.*):$/; print "$F[0] $sh $sp $dh $dp"' |
		tee -a "$OUTPUT_DIR/tcp_udp"
}

info() {
	echo '=== DNS ==='
	awk '{a[$0]++} END {for (x in a) print x,a[x]}' "$1/dns" | sort -k2 -nr | head -n "$2" | column -t
	echo ''
	echo ''

	echo '=== TCP/UDP ==='
	echo '== SRC =='
	awk '{a[$2]++} END {for (x in a) print x,a[x]}' "$1/tcp_udp" | sort -k2 -nr | head -n "$2" | column -t
	echo ''
	echo '== DST =='
	awk '{a[$4]++} END {for (x in a) print x,a[x]}' "$1/tcp_udp" | sort -k2 -nr | head -n "$2" | column -t
	echo ''
	echo '== FLOW =='
	awk '{f=$2":"$3"->"$4":"$5;a[f]++} END {for (x in a) print x,a[x]}' "$1/tcp_udp" | sort -k2 -nr | head -n "$2" | column -t
	echo ''
	echo '== UNDIRECTED FLOW =='
	awk '{f=($2<$4?$2"<->"$4:$4"<->"$2);a[f]++} END {for (x in a) print x,a[x]}' "$1/tcp_udp" | sort -k2 -nr | head -n "$2" | column -t

}

[ "$1" != 'info' ] && {
	dns &
	tcp_udp &
	wait && exit
}

[ -z "$2" ] && echo 'please supply a directory!' && exit 1
info "$2" "${3:-20}"
