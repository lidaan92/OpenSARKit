#!/bin/bash

#-------------------------------------------------------------------------------------------
#	ALOS Level 1.5 FBD Preprocessing
#
#	Dependencies:
#
#		- SAGA GIS 
#		- Sentinel 1 Toolbox
#		- ASF Mapready
#		- gdal
#
#	Written by:
#
#		Andreas Vollrath, FAO Rome
#
#-------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------
#	0 Set up Script variables
#-------------------------------------------------------------------------------------------

# TMP sourcing for Sepal env.
source /data/home/Andreas.Vollrath/github/OpenSARKit_source.bash >/dev/null 2>&1
source /home/avollrath/github/OpenSARKit/OpenSARKit_source.bash >/dev/null 2>&1

#-------------------------------------------------------------------------------------------	
# 	0.1 Check for right usage & set up basic Script Variables
if [ "$#" != "3" ]; then
  echo -e "Usage: osk_ALOS_L1_1_preprocess /path/to/zip /path/to/dem /output/folder"
  echo -e "The path will be your Project folder!"
  exit 1
else
  echo "Welcome to OpenSARKit!"
# set up input data
  FILE=`readlink -f $1`
  PROC_DIR=`dirname ${FILE}`
  TMP_DIR=${PROC_DIR}/TMP
  mkdir -p ${TMP_DIR}
  DEM_FILE=$2
  echo "Processing folder: ${PROC_DIR}"

  mkdir -p $3
  cd $3
  OUT_DIR=`pwd`
fi
#-------------------------------------------------------------------------------------------


#-------------------------------------------------------------------------------------------
# 1 Unzip Archive
#-------------------------------------------------------------------------------------------
echo "Extracting ${FILE}"
unzip -o -q ${FILE} -d ${TMP_DIR}

#-------------------------------------------------------------------------------------------
# 2 Get some scene infos and print them to Std.Out
#-------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------
# extract filenames
SCENE_ID=`ls ${TMP_DIR}`
cd ${TMP_DIR}/${SCENE_ID}
VOLUME_FILE=`ls VOL*`
LEADER_FILE=`ls LED*`
IMAGE_FILE=`ls IMG-HH*`
#-------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------
# check for mode
if grep -q IMG-VV workreport;then

	MODE="PLR"

elif grep -q IMG-HV workreport;then

	MODE="FBD"
	
else

	MODE="FBS"
fi
#-------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------
# extract Date and Footprint etc
YEAR=`cat workreport | grep Img_SceneCenterDateTime | awk -F "=" $'{print $2}' | cut -c 2-5`
MONTH=`cat workreport | grep Img_SceneCenterDateTime | awk -F "=" $'{print $2}' | cut -c 6-7`
DAY=`cat workreport | grep Img_SceneCenterDateTime | awk -F "=" $'{print $2}' | cut -c 7-8`
DATE=`cat workreport | grep Img_SceneCenterDateTime | awk -F "=" $'{print $2}' | cut -c 2-9`
#UL_LAT=`cat workreport | grep Brs_ImageSceneLeftTopLatitude | awk -F "=" $'{print $2}' | sed 's/\"//g'`
#UL_LAT=`cat workreport | grep Brs_ImageSceneLeftTopLatitude | awk -F "=" $'{print $2}' | sed 's/\"//g'`
FRAME=`echo ${SCENE_ID}	| cut -c 12-15`	
ORBIT=`echo ${SCENE_ID}	| cut -c 7-11`	
SAT_PATH=`curl -s https://api.daac.asf.alaska.edu/services/search/param?keyword=value\&granule_list=${SCENE_ID:0:15}\&output=csv | tail -n 1 | awk -F "," $'{print $7}' | sed 's/\"//g'` # !!!!!needs change for final version!!!!!	
	
echo "----------------------------------------------------------------"
echo "Processing Scene: 		${SCENE_ID:0:15}"
echo "Satellite/Sensor: 		ALOS/Palsar"
echo "Acquisiton Mode:		${MODE}"
echo "Acquisition Date (YYYYMMDD):	${DATE}"
echo "Relative Satellite Track: 	${SAT_PATH}"
echo "Image Frame: 			$FRAME"
echo "----------------------------------------------------------------"
#-------------------------------------------------------------------------------------------


#-------------------------------------------------------------------------------------------
# 3 Preprocess imagery part I - Terrain Correction & Geocoding
#-------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------
# define input/output file
INPUT_RAW=${TMP_DIR}/${SCENE_ID}/${IMAGE_FILE}	
OUTPUT_ASF=${TMP_DIR}/${SCENE_ID}
#-------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------
# set up final output directory
FINAL_DIR=$OUT_DIR/${FRAME}-${ORBIT}
mkdir -p ${FINAL_DIR}
#-------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------
# prepare DEM
echo "create DEM crop"
CROP_DEM=${TMP_DIR}/tmp_crop_dem.tif
bash ${GDAL_BIN}/crop_dem.sh ${TMP_DIR}/${SCENE_ID} ${DEM_FILE} ${CROP_DEM}
cd ${TMP_DIR}/${SCENE_ID}
#-------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------
# manipulate ASF config file
cp ${ASF_CONF}/geocoding_alos_l1.5.cfg ${TMP_DIR}/geocoding_alos_fbd.cfg
sed -i "s|model =|model = ${CROP_DEM}|g" ${TMP_DIR}/geocoding_alos_fbd.cfg
sed -i "s|projection =|projection = ${ASF_CONF}/Proj.proj|g" ${TMP_DIR}/geocoding_alos_fbd.cfg 
#-------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------
# do ASF procesing
echo "Importing ${SCENE_ID} from $DATE into ASF and geocode it"
echo "Check logfile ${FINAL_DIR}/log_asf for output"
asf_mapready -quiet -auto-water-mask -input ${INPUT_RAW} -output ${OUTPUT_ASF} -tmpdir ${TMP_DIR}/tmp -log ${FINAL_DIR}/log_asf ${TMP_DIR}/geocoding_alos_fbd.cfg
#-------------------------------------------------------------------------------------------

if grep -q Error ${FINAL_DIR}/log_asf; then 	
	echo "The coregistration seems not to be possible, so we will try without DEM and water mask"
	echo "Check logfile ${FINAL_DIR}/log_asf_no_coreg for output"
	asf_mapready -quiet -no-match -input ${INPUT_RAW} -output ${OUTPUT_ASF} -tmpdir ${TMP_DIR}/tmp -log ${FINAL_DIR}/log_asf_no_coreg ${TMP_DIR}/geocoding_alos_fbd.cfg
fi

#-------------------------------------------------------------------------------------------
# 4 Preprocess imagery II - Speckle Filtering with S1TBX
#-------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------
# define tmp files
OUTPUT_SPK_HH=${TMP_DIR}/Gamma0_HH.tif
OUTPUT_SPK_HV=${TMP_DIR}/Gamma0_HV.tif
OUTPUT_ASF=${TMP_DIR}/${SCENE_ID}
#-------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------
# manipulate xml Graph for S1TBX processing
cp ${S1TBX_GRAPHS}/Refined_Lee.xml ${TMP_DIR}/Refined_Lee.xml  
# insert Input file path into processing chain xml
sed -i "s|INPUT|${OUTPUT_ASF}"_GAMMA-HH.tif"|g" ${TMP_DIR}/Refined_Lee.xml  
# insert Input file path into processing chain xml
sed -i "s|OUT_LEE|${OUTPUT_SPK_HH}|g" ${TMP_DIR}/Refined_Lee.xml  
#-------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------
# Launch S1TBX for HH channel speckle filtering
echo "Apply Multi-look & Speckle Filter to ${SCENE_ID}"
sh ${S1TBX_EXE} ${TMP_DIR}/Refined_Lee.xml 2>&1 | tee  ${TMP_DIR}/tmplog
#-------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------
# in case it fails because of Java error, try it a second time
if grep -q Error ${TMP_DIR}/tmplog; then 	
	echo "2nd try"
	rm -rf ${OUTPUT_SPK_HH} 
	sh ${S1TBX_EXE} ${TMP_DIR}/Refined_Lee.xml 2>&1 | tee  ${TMP_DIR}/tmplog
fi
rm -f ${TMP_DIR}/Refined_Lee.xml 
#-------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------
# do the same for HV channel
cp ${S1TBX_GRAPHS}/Refined_Lee.xml ${TMP_DIR}/Refined_Lee.xml  
# insert Input file path into processing chain xml
sed -i "s|INPUT|${OUTPUT_ASF}"_GAMMA-HV.tif"|g" ${TMP_DIR}/Refined_Lee.xml  
# insert Input file path into processing chain xml
sed -i "s|OUT_LEE|${OUTPUT_SPK_HV}|g" ${TMP_DIR}/Refined_Lee.xml  

echo "Apply Multi-look & Speckle Filter to ${SCENE_ID}"
sh ${S1TBX_EXE} ${TMP_DIR}/Refined_Lee.xml 2>&1 | tee  ${TMP_DIR}/tmplog

if grep -q Error ${TMP_DIR}/tmplog; then 	
	echo "2nd try"
	rm -rf ${OUTPUT_SPK_HV} 
	sh ${S1TBX_EXE} ${TMP_DIR}/Refined_Lee.xml 2>&1 | tee  ${TMP_DIR}/tmplog
fi
#-------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------
# 5 Preprocess imagery III - Mask Layover/Shadow and interpolate small data holes 
#-------------------------------------------------------------------------------------------


#-------------------------------------------------------------------------------------------
echo "Inverting Layover/Shadow Mask"	
gdal_calc.py -A ${TMP_DIR}/${SCENE_ID}/layover_mask.tif --outfile=${TMP_DIR}/mask.tif --calc="1*(A==1)" --NoDataValue=0
#-------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------
# translate to SAGA format
gdalwarp -srcnodata 0 -dstnodata -99999 -of SAGA ${OUTPUT_SPK_HH} ${TMP_DIR}/tmp_hh_saga.sdat
gdalwarp -srcnodata 0 -dstnodata -99999 -of SAGA ${OUTPUT_SPK_HV} ${TMP_DIR}/tmp_hv_saga.sdat
gdalwarp -srcnodata 0 -dstnodata -99999 -of SAGA ${TMP_DIR}/mask.tif ${TMP_DIR}/tmp_mask.sdat
#-------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------
echo "Masking out Layover/Shadow regions"
saga_cmd -f=r grid_calculus 1 -GRIDS:${TMP_DIR}/tmp_hh_saga.sgrd -XGRIDS:${TMP_DIR}/tmp_mask.sgrd -RESULT ${TMP_DIR}/tmp_mask_hh_saga.sgrd -FORMULA:"a * b"
saga_cmd -f=r grid_calculus 1 -GRIDS:${TMP_DIR}/tmp_hv_saga.sgrd -XGRIDS:${TMP_DIR}/tmp_mask.sgrd -RESULT ${TMP_DIR}/tmp_mask_hv_saga.sgrd -FORMULA:"a * b"
#-------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------
echo "Filling small data holes by IDW interpolation"
saga_cmd -f=r grid_tools 25 -GRID:${TMP_DIR}/tmp_mask_hh_saga.sgrd -MAXGAPCELLS:250 -MAXPOINTS:500 -LOCALPOINTS:25 -CLOSED:${TMP_DIR}/tmp_mask_hh_filled.sgrd
saga_cmd -f=r grid_tools 25 -GRID:${TMP_DIR}/tmp_mask_hv_saga.sgrd -MAXGAPCELLS:250 -MAXPOINTS:500 -LOCALPOINTS:25 -CLOSED:${TMP_DIR}/tmp_mask_hv_filled.sgrd
#-------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------
echo "Create Final Output files"
gdalwarp -srcnodata -99999 -dstnodata 0 ${TMP_DIR}/tmp_mask_hh_filled.sdat ${FINAL_DIR}/Gamma0_HH.tif
gdalwarp -srcnodata -99999 -dstnodata 0 ${TMP_DIR}/tmp_mask_hv_filled.sdat ${FINAL_DIR}/Gamma0_HV.tif
#-------------------------------------------------------------------------------------------

#-------------------------------------------------------------------------------------------
# remove Temp Folder
rm -rf ${TMP_DIR}
#-------------------------------------------------------------------------------------------
echo "------------------------------------------------------------"
echo "Successfully preprocessed ${SCENE_ID} (OpenSARKit Statement)"
echo "------------------------------------------------------------"
#EOF