import pandas
import os
import os.path

##--------------------------------------------------------------------
## Simulation suite
##--------------------------------------------------------------------
# simsuite = 'fluxnet'
simsuite = 'pmodel_test'

##--------------------------------------------------------------------
## Compile
##--------------------------------------------------------------------
if simsuite == 'fluxnet':
    if not os.path.exists( 'runpmodel' ):
        call(['make', 'pmodel'])

##--------------------------------------------------------------------
## Get site names
##--------------------------------------------------------------------
filnam_siteinfo_csv = '../input_' + simsuite + '_sofun/siteinfo_' + simsuite + '_sofun.csv'

if os.path.exists( filnam_siteinfo_csv ):
    print 'reading site information file ...'
    siteinfo_sub_dens = pandas.read_csv( '../input_' + simsuite + '_sofun/siteinfo_' + simsuite + '_sofun.csv' )
else:
    print 'site info file does not exist: ' + filnam_siteinfo_csv
    
##--------------------------------------------------------------------
## Loop over site names and submit job for each site
##--------------------------------------------------------------------
siteinfo = pandas.read_csv( filnam_siteinfo_csv )
sitenames = siteinfo['mysitename']
for idx in sitenames:
  print 'submitting job for site ' + idx + '...'
  os.system( 'echo ' + idx + '| ./runpmodel' )