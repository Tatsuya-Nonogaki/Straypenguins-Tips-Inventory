#!/usr/bin/python
import time
import getopt
import sys
import re

def print_help():
   print 'change_server_listenport.py --domain <domain-home> -s <server-name> --port <listen-port>'

def print_value(holder):
   val=get(holder)
   print holder, '=', val

# Get setting specification.
listonly=0
domainDir = ''
svName = ''
port = ''
try:
   opts, args = getopt.getopt(sys.argv[1:],"d:s:o:lh",["domain=","svname=","port="])
except getopt.GetoptError:
   print_help()
   sys.exit(2)
for opt, arg in opts:
   if opt == '-h':
      print_help()
      sys.exit()
   elif opt == '-l':
      listonly = 1
   elif opt in ("-d", "--domain"):
      domainDir = arg
   elif opt in ("-s", "--svname"):
      svName = arg
   elif opt in ("-o", "--port"):
      port = arg
print 'domainDir =', domainDir
print 'svName =', svName
print 'port =', port

if not domainDir:
   print_help()
   sys.exit(2)
elif not svName:
   print_help()
   sys.exit(2)
elif (port=='' and not listonly):
   print_help()
   sys.exit(2)

# Manage Server listen port.
readDomain(domainDir)
cd('/Servers/' + svName)

if not listonly:
   cmo.setListenPort(port)

print '\n---- Result:'
print_value('ListenPort')
print ""

if not listonly:
   updateDomain()

exit()
