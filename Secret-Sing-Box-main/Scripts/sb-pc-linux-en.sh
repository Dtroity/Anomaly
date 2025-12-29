#!/bin/bash

textcolor='\033[1;36m'
red='\033[1;31m'
clear='\033[0m'

check_root() {
	if [[ $EUID -ne 0 ]]
	then
		echo ""
		echo -e "${red}Error: this script should be run as root, use \"sudo -i\" command first${clear}"
		echo ""
		exit 1
	fi
}

check_sbmanager() {
	if [[ -f /usr/local/bin/sbmanager ]] && [[ ! -f /usr/local/bin/proxylist ]]
	then
		echo ""
		echo -e "${red}Error: this script should be run on the client device, not on the server${clear}"
		echo ""
		exit 1
	fi
}

banner() {
	echo ""
	echo "╔══╗ ╔══╗ ╦══╗"
	echo "║    ║    ║  ║"
	echo "╚══╗ ╚══╗ ╠══╣"
	echo "   ║    ║ ║  ║"
	echo "╚══╝ ╚══╝ ╩══╝"
}

install_sing_box() {
	[[ ! -f /usr/local/bin/proxylist ]] && touch /usr/local/bin/proxylist

	if [ $(sing-box version &> /dev/null; echo $?) -ne 0 ]
	then
		echo ""
		echo -e "${textcolor}Sing-Box is not installed${clear}"
		echo ""
		echo -e "${textcolor}[?]${clear} Press ${textcolor}Enter${clear} to install it or enter ${textcolor}x${clear} to exit:"
		read sbinstall
		exit_install

		echo -e "${textcolor}Installing Sing-Box...${clear}"
		[ ! -d /etc/apt/keyrings ] && mkdir /etc/apt/keyrings
		curl -fsSL https://sing-box.app/gpg.key -o /etc/apt/keyrings/sagernet.asc
		chmod a+r /etc/apt/keyrings/sagernet.asc
		echo "deb [arch=`dpkg --print-architecture` signed-by=/etc/apt/keyrings/sagernet.asc] https://deb.sagernet.org/ * *" | tee /etc/apt/sources.list.d/sagernet.list > /dev/null
		apt-get update -y
		apt-get install sing-box -y
		systemctl disable sing-box.service
		echo ""

		if [ $(sing-box version &> /dev/null; echo $?) -eq 0 ]
		then
			echo -e "${textcolor}Sing-Box is installed${clear}"
			echo ""
			echo -e "It can be updated with ${textcolor}apt-get install sing-box -y${clear} command"
			echo ""
			main_menu
		else
			echo -e "${red}Error: Sing-Box has not been installed${clear}"
			echo ""
			exit 1
		fi
	fi
}

exit_install() {
	if [[ "$sbinstall" == "x" ]] || [[ "$sbinstall" == "х" ]]
	then
		echo ""
		exit 0
	fi
}

exit_add_proxy() {
	if [[ "$link" == "x" ]] || [[ "$link" == "х" ]]
	then
		link=""
		main_menu
	fi
}

exit_del_proxy() {
	if [[ "$delcomm" == "x" ]] || [[ "$delcomm" == "х" ]]
	then
		delcomm=""
		main_menu
	fi
}

check_link() {
	while [[ -z $link ]] || [[ -z $(echo "$(curl -s ${link})" | grep '"tag": "proxy"') ]]
	do
		if [[ -z $link ]]
		then
			:
		else
			echo -e "${red}Error: the link is incorrect or the server is not available${clear}"
			echo ""
		fi
		echo -e "${textcolor}[?]${clear} Enter your client config link or enter ${textcolor}x${clear} to exit:"
		read link
		[[ -n $link ]] && echo ""
		exit_add_proxy
	done
}

check_command_add() {
	while [[ $(which ${newcomm} &> /dev/null; echo $?) -eq 0 ]] || [[ -z $newcomm ]] || [[ ! $newcomm =~ ^[a-zA-Z0-9_-]+$ ]]
	do
		if [[ $(which ${newcomm} &> /dev/null; echo $?) -eq 0 ]]
		then
			echo -e "${red}Error: this command already exists${clear}"
			echo ""
		elif [[ -z $newcomm ]]
		then
			:
		else
			echo -e "${red}Error: the command should contain only letters, numbers, _ and - symbols${clear}"
			echo ""
		fi
		echo -e "${textcolor}[?]${clear} Enter the command for the new proxy:"
		read newcomm
		[[ -n $newcomm ]] && echo ""
	done
}

check_command_del() {
	while [[ -z $delcomm ]] || [[ ! -f /usr/local/bin/${delcomm} ]]
	do
		if [[ -z $delcomm ]]
		then
			:
		else
			echo -e "${red}Error: this command does not exist in /usr/local/bin/${clear}"
			echo ""
		fi
		echo -e "${textcolor}[?]${clear} Enter the proxy command you want to delete or enter ${textcolor}x${clear} to exit:"
		read delcomm
		[[ -n $delcomm ]] && echo ""
		exit_del_proxy
	done
}

show_proxies() {
	proxynum=$(cat /usr/local/bin/proxylist | wc -l)
	echo -e "${textcolor}Number of proxies:${clear} ${proxynum}"
	cat /usr/local/bin/proxylist | sed "s/#//g"
	echo ""
	main_menu
}

add_proxies() {
	while [[ $link != "x" ]] && [[ $link != "х" ]]
	do
		echo -e "${textcolor}[?]${clear} Enter your client config link or enter ${textcolor}x${clear} to exit:"
		read link
		[[ -n $link ]] && echo ""
		exit_add_proxy
		check_link
		echo -e "${textcolor}[?]${clear} Enter the command for the new proxy:"
		read newcomm
		[[ -n $newcomm ]] && echo ""
		check_command_add

		cat > /usr/local/bin/${newcomm} <<-EOF
		#!/bin/bash
		textcolor='\033[1;36m'
		red='\033[1;31m'
		clear='\033[0m'
		if [[ \$EUID -ne 0 ]]
		then
		    echo ""
		    echo -e "\${red}Error: this command should be run with sudo or as root\${clear}"
		    echo ""
		    exit 1
		fi
		echo ""
		echo -e "\${textcolor}Started Sing-Box\${clear}"
		echo "Do not close this window while Sing-Box is running"
		echo -e "Press \${textcolor}Ctrl + C\${clear} to disconnect"
		echo ""
		wget -q -O /etc/sing-box/config-1.json ${link} && mv -f /etc/sing-box/config-1.json /etc/sing-box/config.json
		sing-box run -c /etc/sing-box/config.json
		EOF

		chmod +x /usr/local/bin/${newcomm}
		echo "#${newcomm}" >> /usr/local/bin/proxylist
		echo -e "Command ${textcolor}${newcomm}${clear} has been added to /usr/local/bin/, use it to connect to the proxy"
		echo ""
	done

	main_menu
}

delete_proxies() {
	while [[ $delcomm != "x" ]] && [[ $delcomm != "х" ]]
	do
		echo -e "${textcolor}[?]${clear} Enter the proxy command you want to delete or enter ${textcolor}x${clear} to exit:"
		read delcomm
		[[ -n $delcomm ]] && echo ""
		exit_del_proxy
		check_command_del

		rm /usr/local/bin/${delcomm}
		sed -i "/#$delcomm/d" /usr/local/bin/proxylist
		echo -e "Command ${textcolor}${delcomm}${clear} has been deleted from /usr/local/bin/"
		echo ""
	done

	main_menu
}

main_menu() {
	echo ""
	echo -e "${textcolor}Select an option:${clear}"
	echo "0 - Exit"
	echo "1 - Show the list of proxies"
	echo "2 - Add a new proxy"
	echo "3 - Delete a proxy"
	read option
	echo ""

	case $option in
		1)
		show_proxies
		;;
		2)
		add_proxies
		;;
		3)
		delete_proxies
		;;
		*)
		exit 0
	esac
}

check_root
check_sbmanager
banner
install_sing_box
main_menu