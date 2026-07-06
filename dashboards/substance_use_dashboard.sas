* The dashboard updates once year when the new deaths data of previous year is finalized before the end of August;
* Last updated by PJ Wu, 10,20,2025;





%include 'S:\ANALYTICS\PUBLICATIONS\DASHBOARDS\Published\Substance Use\Updated Format - All Substances\Format Substance Use.sas'; 
libname death "S:\Data\deaths";
libname hosp "S:\DATA\Statewide Hospital Billing Data";
libname pop 'S:\DATA\demographics';
options compress = BINARY;
ods select none;

%let start_year = 10; *change this to the last 2 digits of the desired starting year, the current dashboard starts with 2010 data;
%let end_year = 24; *change this to the last 2 digits of the desired ending year, the dashboard updates with previous year's data when the deaths data finalized before the end of August;

/*----------------------------------------------POPULATION----------------------------------------------*/

data pop;
set pop.population_vintage_2025;  *update this when new data is available;
where with_prisoners=1 & 20&start_year.<=year<=20&end_year.;
if sex = 0 then sex = 2;
run;

proc sql;   *SQL code for population by year, county, with (sex, race/ethnicity, and age);
create table pop_sex as
	select distinct 
	year, 
	county,
	sex,
	sum(population) as pop_sum
	from pop
	group by year, county, sex;

create table pop_race as
	select distinct 
	year, 
	county, 
	race_ethnicity,
	sum(population) as pop_sum
	from pop
	group by year, county, race_ethnicity;

create table pop_age as
	select distinct 
	year, 
	county,
	age_grp1,
	sum(population) as pop_sum
	from pop
	group by year, county, age_grp1;
quit;


data pop_co;
set pop_sex pop_race pop_age;
run;

proc delete data = pop pop_sex pop_race pop_age; *delete these tables to save storage space;
run;

/*----------------------------------------------END OF POPULATION----------------------------------------------*/





/*----------------------------------------------DEATH----------------------------------------------*/


%macro death (yr1,yr2);

%do i = &yr1. %to &yr2.;
	data d&i.;
		set death.death_20&i.;
			ICD10_3 = substrn (icd_code,1,3);
run;
%end;

%mend;


%death (&start_year.,&end_year.);




data death_all;
	set	d&start_year. - d&end_year.;
		where res_st=29;
			if ("X40"<=ICD10_3<="X45" or "X60"<=ICD10_3<="X65" or ICD10_3="X85" or "Y10"<=ICD10_3<="Y15"); /*<-- this includes alochol*/
    			 					
  alcohol=0;	
  allsubstances=1;  				
  stimulant=0;
  opioid=0;			

	ARRAY drugs (20) $ axis_1--axis_20 ;
		DO i = 1 to 20;
		    if drugs(i) in ("T510","T511","T512","T513","T518","T519",'X45','X65','Y15') then alcohol=1;
			if drugs(i) in ("T405","T436") then stimulant=1;
		    if drugs(i) in ("T400","T401","T402","T403","T404","T406") then opioid=1; 
		END; 


if sex=3 then sex = 9;

	rename age_grp1=age_var;
run;


/*-------------------------------------------------------------------------------------------------------------*/
*Below syntax makes data holders for race_ethnchs, sex, and age.;

data race_ethnchs_year;
	do year = 20&start_year. to 20&end_year.;
	do race_ethnchs = 1 to 5,8,9;
	do res_co = 1 to 17,88,99;
		output;
	end;
	end;
	end;
run;

data sex_year;
	do year = 20&start_year. to 20&end_year.;
	do sex=1,2,9;
	do res_co = 1 to 17,88,99;
		output;
	end;
	end;
	end;
run;

data age_var_year;
	do year = 20&start_year. to 20&end_year.;
	do age_var = 1 to 11,99;
	do res_co = 1 to 17,88,99;
		output;
	end;
	end;
	end;
run;
/*-------------------------------------------------------------------------------------------------------------*/


%macro deathcount (drug, var);
proc tabulate data = death_all out = o_death&drug&var(drop=_type_ _page_ _table_) missing ;
where &drug = 1;
	class cert_yr;
	class &drug;
	class &var;
	class res_co/preloadfmt;
	table cert_yr*res_co*&drug*&var/printmiss misstext='0';
format res_co county.;
run;


*make missing counts to 0, so the dashboard would still have those categories;
proc sql;
create table death&drug&var as
	select distinct
		a.&var ,
		a.year as cert_yr,
		a.res_co,
		case when b.n = . then b.n = 0 else b.n
		end as N
	from &var._year as a 
	left outer join o_death&drug&var as b
	on a.&var = b.&var and a.year = b.cert_yr and a.res_co=b.res_co 
;
quit;


%mend;
%deathcount (alcohol, sex);
%deathcount (alcohol, race_ethnchs);
%deathcount (alcohol, age_var);

%deathcount (opioid, sex);
%deathcount (opioid, race_ethnchs);
%deathcount (opioid, age_var);

%deathcount (stimulant, sex);
%deathcount (stimulant, race_ethnchs);
%deathcount (stimulant, age_var);

%deathcount (allsubstances, sex);
%deathcount (allsubstances, race_ethnchs);
%deathcount (allsubstances, age_var);






%macro demo (file, var, var2);
data &file.2;
set  &file;
length Demographic $50;

if sex = 1 then Demographic = "Male";
else if sex = 2 then Demographic = "Female";
else if sex = 9 then Demographic = "Unknown Sex";

if race_ethnchs = 1 then Demographic = 'Non-Hispanic White';
else if race_ethnchs = 2 then Demographic = 'Non-Hispanic Black';
else if race_ethnchs = 3 then Demographic = 'Non-Hispanic American Indian or Alaska Native';
else if race_ethnchs = 4 then Demographic = 'Non-Hispanic Asian/Pacific Islander';
else if race_ethnchs = 5 then Demographic = 'Hispanic';
else if race_ethnchs = 8 then Demographic = 'Other';
else if race_ethnchs = 9 then Demographic = 'Unknown Race';


if age_var = 1 then Demographic = '<1';
else if age_var = 2 then Demographic =	'1-4';
else if age_var = 3 then Demographic = '5-14';
else if age_var = 4 then Demographic = '15-24';
else if age_var = 5 then Demographic = '25-34';
else if age_var = 6 then Demographic = '35-44';
else if age_var = 7 then Demographic = '45-54';
else if age_var = 8 then Demographic = '55-64';
else if age_var = 9 then Demographic = '65-74';
else if age_var = 10 then Demographic = '75-84';
else if age_var = 11 then Demographic = '85+';
else if age_var = 99 then Demographic = 'Unknown Age';

drug_grp = &var2;

Source = 'Death';
Type = 'Death';

run;


%mend;
%demo (deathalcoholsex, sex, 1);
%demo (deathalcoholrace_ethnchs, race_ethnchs, 1);
%demo (deathalcoholage_var, age_var, 1);

%demo (deathstimulantsex, sex, 2);
%demo (deathstimulantrace_ethnchs, race_ethnchs, 2);
%demo (deathstimulantage_var, age_var, 2);

%demo (deathopioidsex, sex, 3);
%demo (deathopioidrace_ethnchs, race_ethnchs, 3);
%demo (deathopioidage_var, age_var, 3);

%demo (deathallsubstancessex, sex, 4);
%demo (deathallsubstancesrace_ethnchs, race_ethnchs, 4);
%demo (deathallsubstancesage_var, age_var, 4);

data death_current;
set 
deathalcoholsex2 deathalcoholrace_ethnchs2 deathalcoholage_var2
deathopioidsex2 deathopioidrace_ethnchs2 deathopioidage_var2
deathstimulantsex2 deathstimulantrace_ethnchs2 deathstimulantage_var2
deathallsubstancessex2 deathallsubstancesrace_ethnchs2 deathallsubstancesage_var2;
run;



proc sql;
	create table death_final as
	select
		a.*,
		b.pop_sum
			from death_current as a 
			left join  pop_co as b
			on a.cert_yr = b.year and a.res_co = b.county and a.age_var = b.age_grp1 and a.race_ethnchs = b.race_ethnicity and a.sex = b.sex;

quit;



data death_final2;
set death_final;
if n = . then n = 0;
if pop_sum = . then pop_sum = 0;
rename cert_yr = Year res_co = County pop_sum = Population drug_grp = Drug;
format drug_grp drug_grp. res_co county.;
drop race_ethnchs age_var sex ;
run;


proc delete data = 
D&start_year. - D&end_year. 
deathalcoholsex   	   deathalcoholrace_ethnchs   	   deathalcoholage_var   	  deathalcoholsex2   	  deathalcoholrace_ethnchs2  	   deathalcoholage_var2
deathopioidsex    	   deathopioidrace_ethnchs    	   deathopioidage_var    	  deathopioidsex2    	  deathopioidrace_ethnchs2    	   deathopioidage_var2		
deathstimulantsex 	   deathstimulantrace_ethnchs 	   deathstimulantage_var 	  deathstimulantsex2 	  deathstimulantrace_ethnchs2 	   deathstimulantage_var2 
deathallsubstancessex  deathallsubstancesrace_ethnchs  deathallsubstancesage_var  deathallsubstancessex2  deathallsubstancesrace_ethnchs2  deathallsubstancesage_var2
Death_all         	   Death_current              	   Death_final ;
				
run;

/*----------------------------------------------END OF DEATH----------------------------------------------*/











/*----------------------------------------------HOSPITAL----------------------------------------------*/


/*Combine and Flag Hospital Data Sets*/
%macro billing (yr1,yr2,type, payer2, payer3);
%do i = &yr1. %to &yr2.;
		%if (i <= 15) %then %do;
	data &type._20&i. &type._od_20&i;
	set hosp.&type.20&i (keep = DischYear patzip patstatecode diag01-diag33 ecode1-ecode4 DischDate Payer1_val race_val Gender_val AgeInYears PatFIPS AdmitDate
	 &payer2 &payer3 /* <-----Comment out for ED and comment in for IP */
);
    where patzip like '89%' & upcase (patstatecode) = "NV";


	    array d (*) diag01-diag33;
		array e (*) ecode1-ecode4;
		if (DischDate < '01OCT2015'd) then do;
			do i = 1 to dim(d);

			if substr(d{i},1,4) in ('3050') then alcohol=1; /*Behavioral all DX*/
			if substr(d{i},1,3) in ('291','303') then alcohol=1; /*Behavioral all DX*/
			if substr(diag01,1,3) in ('980') then alcohol_od=1; /*Poisoning primary */

			if substr(d{i},1,4) in ('3040','3047','3055') then opioid=1;
			if substr(diag01,1,4) in ('9650') then opioid_od=1;

			if substr(d{i},1,4) in ('3042','3044','3056','3057') then stimulant=1;
			if substr(diag01,1,5) in ('97081') then stimulant_od=1;
			if substr(diag01,1,4) in ('9697') then stimulant_od=1;

	 		if substr(d{i},1,3) in ('291','304','303') then ALL=1; /*need to exclude 292.89 */
			if substrn(d{i},1,3) = '292' and substrn(d{i},4,2) ~= '89' then allsubstances=1;
			if substrn(d{i},1,3) = '305' and substrn(d{i},4,1) ~= '1' then allsubstances=1;
			if ('960' <= substr(diag01,1,3) <=  '980') then allsubstances_od=1;

		end;

			do i = 1 to dim(e);

			if substrn(e{i},1,4) = "E860" then alcohol_od=1;
 			if substrn(e{i},1,5) in ('E8500','E8501','E8502') then opioid_od=1;
 			if substrn(e{i},1,5) in ('E8542','E8543') then stimulant_od=1;
			if ('E950' <= substrn(e{i},1,4) <=  'E952') then allsubstances_od=1;
			if substrn(e{i},1,4) = 'E962' then allsubstances_od=1;
			if ('E850' <= substrn(e{i},1,4) <=  'E858') then allsubstances_od=1;

			end;
		end; 

	if (DischDate >= '01OCT2015'd) then do;/*CS Poisoning -> Dependance Tab*/
		do i=1 to dim(d);

/*Alcohol*/
			if substr(d{i},1,3) = 'F10' then alcohol=1; 
			if substr(diag01,1,3) = 'T51' then alcohol_od=1; 

/*Opioids*/
			if substr(d{i},1,3) in ("F11") then opioid=1;
			if (('T400' <= substr(diag01,1,4) <= 'T404') & (substr(diag01,6,2) in ('1A','2A','3A','4A','1D','2D','3D','4D'))) | 
  		   		((substr(diag01,1,4) = 'T406')  & (substr(diag01,6,2) in ('1A','2A','3A','4A','1D','2D','3D','4D')))
					then opioid_od=1;   
/*Methadone*/
			if ((substr(diag01,1,4) = 'T403') & (substr(diag01,6,2) in ('1A','2A','3A','4A','1D','2D','3D','4D'))) 
					then methadone_od=1;  
/*Fentanyl*/
			if ((substr(diag01,1,5) = 'T4041') & (substr(diag01,6,2) in ('1A','2A','3A','4A','1D','2D','3D','4D'))) 
					then fentanyl_od=1;    

/*Stimulants*/
			if substr(d{i},1,3) in ("F14","F15") then stimulant=1;
			if (substrn(diag01,1,4) in ("T405" "T436") & (substr(diag01,6,2) in ('1A','2A','3A','4A','1D','2D','3D','4D'))) then stimulant_od=1;


			if ('F10' <= (substr(d{i},1,3)) <= 'F16') | substr(d{i},1,3) = 'F19' then allsubstances=1;
			if (('T36' <= substr(diag01,1,3) <= 'T51') & (substr(diag01,6,2) in ('1A','2A','3A','4A','1D','2D','3D','4D'))) then allsubstances_od=1; 

			end;
		end; 

	

	if alcohol=1 | stimulant=1 | opioid=1 | allsubstances=1 then output &type._20&i.;
	if alcohol_od=1 | stimulant_od=1 | opioid_od=1| | methadone_od =1 | fentanyl_od = 1 | allsubstances_od=1 then output &type._od_20&i;

run;
		%end; 

	%if (i > 15) %then %do;/*CS Poisoning -> Dependance Tab*/
	data &type._20&i. &type._od_20&i;
	set hosp.&type.20&i (keep = DischYear patzip patstatecode diag01-diag33 DischDate Payer1_val race_val Gender_val AgeInYears PatFIPS AdmitDate
	 &payer2 &payer3 /* <-----Comment out for ED and comment in for IP */
);
    where patzip like '89%' & upcase (patstatecode) = "NV";
	    array d (*) diag01-diag33;
		do i=1 to dim(d);

/*Alcohol*/
			if substr(d{i},1,3) = 'F10' then alcohol=1; 
			if substr(diag01,1,3) = 'T51' then alcohol_od=1; 

/*Opioids*/
			if substr(d{i},1,3) in ("F11") then opioid=1;
			if (('T400' <= substr(diag01,1,4) <= 'T404') & (substr(diag01,6,2) in ('1A','2A','3A','4A','1D','2D','3D','4D'))) | 
  		   		((substr(diag01,1,4) = 'T406')  & (substr(diag01,6,2) in ('1A','2A','3A','4A','1D','2D','3D','4D')))
					then opioid_od=1;   
/*Methadone*/
			if ((substr(diag01,1,4) = 'T403') & (substr(diag01,6,2) in ('1A','2A','3A','4A','1D','2D','3D','4D'))) 
					then methadone_od=1;  
/*Fentanyl*/
			if ((substr(diag01,1,5) = 'T4041') & (substr(diag01,6,2) in ('1A','2A','3A','4A','1D','2D','3D','4D'))) 
					then fentanyl_od=1;    

/*Stimulants*/
			if substr(d{i},1,3) in ("F14","F15") then stimulant=1;
			if (substrn(diag01,1,4) in ("T405" "T436") & (substr(diag01,6,2) in ('1A','2A','3A','4A','1D','2D','3D','4D'))) then stimulant_od=1;


			if ('F10' <= (substr(d{i},1,3)) <= 'F16') | substr(d{i},1,3) = 'F19' then allsubstances=1;
			if (('T36' <= substr(diag01,1,3) <= 'T51') & (substr(diag01,6,2) in ('1A','2A','3A','4A','1D','2D','3D','4D'))) then allsubstances_od=1; 

			end;

	if alcohol=1 | stimulant=1 | opioid=1 | allsubstances=1 then output &type._20&i.;
	if alcohol_od=1 | stimulant_od=1 | opioid_od=1| | methadone_od =1 | fentanyl_od = 1 | allsubstances_od=1 then output &type._od_20&i;
run;
		%end; 

	

%end;

%mend;



%billing(&start_year., &end_year., ed,); 
%billing(&start_year., &end_year., ip, payer2, payer3 );


					 
/*Drug Realted/Poisonings      */


data ed;
set ed_20&start_year.-ed_20&end_year.; 
Source = 'Emergency Department';
Type = 'Dependence';

	
run;

proc freq data = ed;
table dischyear * methadone_od / nocol norow nopercent out = zzz;
run;


proc delete data = ed_20&start_year.-ed_20&end_year. ;
run;

data ip;
set ip_20&start_year.-ip_20&end_year.;
length los 8;
Source = 'Inpatient';
Type = 'Dependence';
los = intck('day', AdmitDate, DischDate);
drop AdmitDate DischDate;


run;

proc delete data = ip_20&start_year.-ip_20&end_year.;
run;


data dependence_all;
	set ip ed;

	pat_fips=input(patfips,5.);

		if race_val=1 then race_var=3;
		if race_val=2 then race_var=4;
		if race_val=3 then race_var=2;
		if race_val=4 then race_var=1;
		if race_val=5 then race_var=5;
		if race_val=6 then race_var=8;
		if race_val=9 then race_var=9;
		if race_val=0 then race_var=9;
		if race_val=7 then race_var=9;

	if Gender_val='F' then sex_var=2;
	else if Gender_val='M' then sex_var=1;
	else if Gender_val='U' then sex_var=9;
	else sex_var = 9;



		if       AgeInYears  <   1 then age_grp1 = 1;
		if  1 <= AgeInYears  <=  4 then age_grp1 = 2; 
		if  5 <= AgeInYears  <= 14 then age_grp1 = 3;
		if 15 <= AgeInYears  <= 24 then age_grp1 = 4;
		if 25 <= AgeInYears  <= 34 then age_grp1 = 5;
		if 35 <= AgeInYears  <= 44 then age_grp1 = 6;
		if 45 <= AgeInYears  <= 54 then age_grp1 = 7;
		if 55 <= AgeInYears  <= 64 then age_grp1 = 8;
		if 65 <= AgeInYears  <= 74 then age_grp1 = 9;
		if 75 <= AgeInYears  <= 84 then age_grp1 =10;
		if       AgeInYears  >= 85 then age_grp1 =11;

		if pat_fips=32510 then pat_co=1;
		if pat_fips=32001 then pat_co=2;
		if pat_fips=32003 then pat_co=3;
		if pat_fips=32005 then pat_co=4;
		if pat_fips=32007 then pat_co=5;
		if pat_fips=32009 then pat_co=6;
		if pat_fips=32011 then pat_co=7;
		if pat_fips=32013 then pat_co=8;
		if pat_fips=32015 then pat_co=9;
		if pat_fips=32017 then pat_co=10;
		if pat_fips=32019 then pat_co=11;
		if pat_fips=32021 then pat_co=12;
		if pat_fips=32023 then pat_co=13;
		if pat_fips=32027 then pat_co=14;
		if pat_fips=32029 then pat_co=15;
		if pat_fips=32031 then pat_co=16;
		if pat_fips=32033 then pat_co=17;
		if pat_fips=' ' then pat_co=99;
			
		if Payer1_val in (10,27) then medicare=1;
		if payer2 in ('10', '27') then medicare=1;
		if payer3 in ('10', '27') then medicare=1;

		if Payer1_val in (16,17,28) then medicaid=1;
		if payer2 in ('16','17','28') then medicaid=1;
		if payer3 in ('16','17','28') then medicaid=1;

run;

%macro dependence (drug, var, var2);

proc tabulate data = dependence_all out = dependence_&drug&var(drop=_type_ _page_ _table_) missing;
where &drug = 1;

	class dischyear;
	class &drug;
	class &var;
	class source;
	class type;
	class pat_co/preloadfmt;
	table dischyear*pat_co*&drug*&var*source*type/printmiss misstext='0';
	format pat_co county.;
run;

/**********************************************************************************/

data dependence_&drug&var;
set  dependence_&drug&var;
length Demographic $50;

if sex_var = 1 then Demographic = "Male";
else if sex_var = 2 then Demographic = "Female";
else if sex_var = 9 then Demographic = "Unknown Sex";

if race_var = 1 then Demographic = 'Non-Hispanic White';
else if race_var = 2 then Demographic = 'Non-Hispanic Black';
else if race_var = 3 then Demographic = 'Non-Hispanic American Indian or Alaska Native';
else if race_var = 4 then Demographic = 'Non-Hispanic Asian/Pacific Islander';
else if race_var = 5 then Demographic = 'Hispanic';
else if race_var = 8 then Demographic = 'Other';
else if race_var = 9 then Demographic = 'Unknown Race';

if age_grp1 = 1 then Demographic = '<1';
else if age_grp1 = 2 then Demographic =	'1-4';
else if age_grp1 = 3 then Demographic = '5-14';
else if age_grp1 = 4 then Demographic = '15-24';
else if age_grp1 = 5 then Demographic = '25-34';
else if age_grp1 = 6 then Demographic = '35-44';
else if age_grp1 = 7 then Demographic = '45-54';
else if age_grp1 = 8 then Demographic = '55-64';
else if age_grp1 = 9 then Demographic = '65-74';
else if age_grp1 = 10 then Demographic = '75-84';
else if age_grp1 = 11 then Demographic = '85+';
else if age_grp1 = 99 then Demographic = 'Unknown Age';

drug_grp = &var2;
run;


%mend;
%dependence (alcohol, sex_var, 1);
%dependence (alcohol, race_var, 1);
%dependence (alcohol, age_grp1, 1);

%dependence (stimulant, sex_var, 2);
%dependence (stimulant, race_var, 2);
%dependence (stimulant, age_grp1, 2);

%dependence (opioid, sex_var, 3);
%dependence (opioid, race_var, 3);
%dependence (opioid, age_grp1, 3);

%dependence (allsubstances, sex_var, 4);
%dependence (allsubstances, race_var, 4);
%dependence (allsubstances, age_grp1, 4);

data dependence_counts;
set 
dependence_alcoholsex_var 
dependence_alcoholrace_var 
dependence_alcoholage_grp1

dependence_opioidsex_var 
dependence_opioidrace_var 
dependence_opioidage_grp1

dependence_stimulantsex_var 
dependence_stimulantrace_var 
dependence_stimulantage_grp1

dependence_allsubstancessex_var 
dependence_allsubstancesrace_var 
dependence_allsubstancesage_grp1;
run;


proc sql;
	create table dependence_final as
	select
		a.*,
		b.pop_sum
			from dependence_counts as a 
			left join  pop_co as b
			on a.dischyear = b.year and a.pat_co = b.county and a.age_grp1 = b.age_grp1 and a.race_var = b.race_ethnicity and a.sex_var = b.sex;

quit;

data dependence_final2;
set dependence_final;
if n = . then n = 0;
if pop_sum = . then pop_sum = 0;
rename dischyear = Year pat_co = County pop_sum = Population drug_grp = Drug; 
format drug_grp drug_grp. pat_co county.;
drop race_var age_grp1 sex_var alcohol stimulant opioid allsubstances;
run;



proc delete data = 
dependence_alcoholsex_var   	dependence_alcoholrace_var      dependence_alcoholage_grp1     
dependence_opioidsex_var    	dependence_opioidrace_var       dependence_opioidage_grp1      
dependence_stimulantsex_var	    dependence_stimulantrace_var    dependence_stimulantage_grp1   
dependence_allsubstancessex_var dependence_allsubstancesrace_var dependence_allsubstancesage_grp1
   dependence_counts        dependence_final;
				
run;

/*----------------------------------------------END OF HOSPITAL DEPENDENCE----------------------------------------------*/





/*----------------------------------------------HOSPITAL POSIONINGS----------------------------------------------*/

					 
/*Drug Realted/Poisonings      */


data ed_od;
set ed_od_20&start_year.-ed_od_20&end_year.; 
Source = 'Emergency Department';
Type = 'Poison';

run;

proc delete data = ed_od_20&start_year.-ed_od_20&end_year. ;
run;

data ip_od;
set ip_od_20&start_year.-ip_od_20&end_year.;
length los 8;
Source = 'Inpatient';
Type = 'Poison';
los = intck('day', AdmitDate, DischDate);
drop AdmitDate DischDate;


run;

proc delete data = ip_od_20&start_year.-ip_od_20&end_year.;
run;

*%macro chia (outfile, infile, var1, var2, var3);


data poison_all;
	set ip_od ed_od;

	pat_fips=input(patfips,5.);

	if race_val=1 then race_var=3;
		if race_val=2 then race_var=4;
		if race_val=3 then race_var=2;
		if race_val=4 then race_var=1;
		if race_val=5 then race_var=5;
		if race_val=6 then race_var=8;
		if race_val=9 then race_var=9;
		if race_val=0 then race_var=9;
		if race_val=7 then race_var=9;

	if Gender_val='F' then sex_var=2;
	else if Gender_val='M' then sex_var=1;
	else if Gender_val='U' then sex_var=9;
	else sex_var = 9;



		if       AgeInYears  <   1 then age_grp1 = 1;
		if  1 <= AgeInYears  <=  4 then age_grp1 = 2; 
		if  5 <= AgeInYears  <= 14 then age_grp1 = 3;
		if 15 <= AgeInYears  <= 24 then age_grp1 = 4;
		if 25 <= AgeInYears  <= 34 then age_grp1 = 5;
		if 35 <= AgeInYears  <= 44 then age_grp1 = 6;
		if 45 <= AgeInYears  <= 54 then age_grp1 = 7;
		if 55 <= AgeInYears  <= 64 then age_grp1 = 8;
		if 65 <= AgeInYears  <= 74 then age_grp1 = 9;
		if 75 <= AgeInYears  <= 84 then age_grp1 =10;
		if       AgeInYears  >= 85 then age_grp1 =11;

		if pat_fips=32510 then pat_co=1;
		if pat_fips=32001 then pat_co=2;
		if pat_fips=32003 then pat_co=3;
		if pat_fips=32005 then pat_co=4;
		if pat_fips=32007 then pat_co=5;
		if pat_fips=32009 then pat_co=6;
		if pat_fips=32011 then pat_co=7;
		if pat_fips=32013 then pat_co=8;
		if pat_fips=32015 then pat_co=9;
		if pat_fips=32017 then pat_co=10;
		if pat_fips=32019 then pat_co=11;
		if pat_fips=32021 then pat_co=12;
		if pat_fips=32023 then pat_co=13;
		if pat_fips=32027 then pat_co=14;
		if pat_fips=32029 then pat_co=15;
		if pat_fips=32031 then pat_co=16;
		if pat_fips=32033 then pat_co=17;
		if pat_fips=' ' then pat_co=99;

	
		if Payer1_val in (10,27) then medicare=1;
		if payer2 in ('10', '27') then medicare=1;
		if payer3 in ('10', '27') then medicare=1;

		if Payer1_val in (16, 17, 28) then medicaid=1;
		if payer2 in ('16','17','28') then medicaid=1;
		if payer3 in ('16','17','28') then medicaid=1;
run;

%macro poison (drug, var, var2);

proc tabulate data = poison_all out = poison_&drug&var(drop=_type_ _page_ _table_) missing;
where &drug = 1;

	class dischyear;
	class &drug;
	class &var;
	class source;
	class type;
	class pat_co/preloadfmt;
	table dischyear*pat_co*&drug*&var*source*type/printmiss misstext='0';
	format pat_co county.;
run;

/**********************************************************************************/

data poison_&drug&var;
set  poison_&drug&var;
length Demographic $50;

if sex_var = 1 then Demographic = "Male";
else if sex_var = 2 then Demographic = "Female";
else if sex_var = 9 then Demographic = "Unknown Sex";

if race_var = 1 then Demographic = 'Non-Hispanic White';
else if race_var = 2 then Demographic = 'Non-Hispanic Black';
else if race_var = 3 then Demographic = 'Non-Hispanic American Indian or Alaska Native';
else if race_var = 4 then Demographic = 'Non-Hispanic Asian/Pacific Islander';
else if race_var = 5 then Demographic = 'Hispanic';
else if race_var = 8 then Demographic = 'Other';
else if race_var = 9 then Demographic = 'Unknown Race';

if age_grp1 = 1 then Demographic = "<1";
else if age_grp1 = 2 then Demographic =	'1-4';
else if age_grp1 = 3 then Demographic = '5-14';
else if age_grp1 = 4 then Demographic = "15-24";
else if age_grp1 = 5 then Demographic = "25-34";
else if age_grp1 = 6 then Demographic = "35-44";
else if age_grp1 = 7 then Demographic = "45-54";
else if age_grp1 = 8 then Demographic = "55-64";
else if age_grp1 = 9 then Demographic = "65-74";
else if age_grp1 = 10 then Demographic = "75-84";
else if age_grp1 = 11 then Demographic = "85+";
else if age_grp1 = 99 then Demographic = "Unknown Age";

drug_grp = &var2;
run;


%mend;
%poison (alcohol_od, sex_var, 1);
%poison (alcohol_od, race_var, 1);
%poison (alcohol_od, age_grp1, 1);

%poison (stimulant_od, sex_var, 2);
%poison (stimulant_od, race_var, 2);
%poison (stimulant_od, age_grp1, 2);

%poison (opioid_od, sex_var, 3);
%poison (opioid_od, race_var, 3);
%poison (opioid_od, age_grp1, 3);

%poison (allsubstances_od, sex_var, 4);
%poison (allsubstances_od, race_var, 4);
%poison (allsubstances_od, age_grp1, 4);

data poison_counts;
set 
poison_alcohol_odsex_var 
poison_alcohol_odrace_var 
poison_alcohol_odage_grp1 

poison_opioid_odsex_var 
poison_opioid_odrace_var 
poison_opioid_odage_grp1

poison_stimulant_odsex_var 
poison_stimulant_odrace_var 
poison_stimulant_odage_grp1

poison_allsubstances_odsex_var 
poison_allsubstances_odrace_var 
poison_allsubstances_odage_grp1;
run;


proc sql;
	create table poison_final as
	select
		a.*,
		b.pop_sum
			from poison_counts as a 
			left join  pop_co as b
			on a.dischyear = b.year and a.pat_co = b.county and a.age_grp1 = b.age_grp1 and a.race_var = b.race_ethnicity and a.sex_var = b.sex;

quit;

data poison_final2;
set poison_final;
if n = . then n = 0;
if pop_sum = . then pop_sum = 0;
rename dischyear = Year pat_co = County pop_sum = Population drug_grp = Drug; 
format drug_grp drug_grp. pat_co county.;
drop race_var age_grp1 sex_var alcohol_od stimulant_od opioid_od allsubstances_od;
run;

proc delete data = 
poison_alcohol_odsex_var   	poison_alcohol_odrace_var      poison_alcohol_odage_grp1     
poison_opioid_odsex_var    	poison_opioid_odrace_var       poison_opioid_odage_grp1      
poison_stimulant_odsex_var	    poison_stimulant_odrace_var    poison_stimulant_odage_grp1   
poison_allsubstances_odsex_var poison_allsubstances_odrace_var poison_allsubstances_odage_grp1
   poison_counts        poison_final  ;
				
run;


/*----------------------------------------------END OF HOSPITAL POSIONINGS----------------------------------------------*/






/*----------------------------------------------LENGTH OF STAY----------------------------------------------*/

%macro los (var, var2, var3);
proc tabulate data = Dependence_all out = los_dependence_&var(drop=_type_ _page_ _table_) missing;
where &var = 1 and source = 'Inpatient';
	class dischyear;
	class &var;
	class los;
	class Type;
	class pat_co/preloadfmt;
	table dischyear*pat_co*&var*los*type/printmiss misstext='0';
	format pat_co county.;

run;

data los_dependence_&var;
set los_dependence_&var;
drug_grp = &var3;
Source = 'Inpatient';
run; 

proc tabulate data = poison_all out = los_poison_&var2(drop=_type_ _page_ _table_) missing;
where &var2 = 1 and source = 'Inpatient';
	class dischyear;
	class &var2;
	class los;
	class type;
	class pat_co/preloadfmt;
	table dischyear*pat_co*&var2*los*type/printmiss misstext='0';
	format pat_co county.;

run;

data los_poison_&var2;
set los_poison_&var2;
drug_grp = &var3;
Source = 'Inpatient';
run; 


%mend;
%los (alcohol, alcohol_od, 1);
%los (stimulant, stimulant_od, 2);
%los (opioid, opioid_od, 3);
%los (allsubstances, allsubstances_od, 4);


data  los_dependence;
set los_dependence_alcohol los_dependence_stimulant los_dependence_opioid los_dependence_allsubstances;
type = 'Dependence';
source = 'Inpatient';
run;

data  los_poison;
set los_poison_alcohol_od los_poison_stimulant_od los_poison_opioid_od los_poison_allsubstances_od;

type = 'Poison';
source = 'Inpatient';
run;

data los_final;
set los_dependence los_poison;
where los >= 0;
if n = . then n = 0;
rename dischyear = Year pat_co = County drug_grp = Drug los = Days N = Count;
format drug_grp drug_grp.;
drop alcohol alcohol_od stimulant stimulant_od opioid opioid_od allsubstances allsubstances_od;
run;

proc delete data = los_dependence_alcohol los_dependence_stimulant los_dependence_opioid los_dependence_allsubstances
				   los_poison_alcohol_od los_poison_stimulant_od los_poison_opioid_od los_poison_allsubstances_od 
				   los_dependence los_poison;
run;

/*----------------------------------------------END LENGTH OF STAY----------------------------------------------*/



/*----------------------------------------------MEDICARE/MEDICAID----------------------------------------------*/
%macro med (med, var, var2, var3);
proc tabulate data = Dependence_all out = &med._d_&var(drop=_type_ _page_ _table_) missing;
where &var = 1;
	class dischyear;
	class &var;
	class los;
	class Type;
	class source;
	class &med;
	class pat_co/preloadfmt;
	table dischyear*pat_co*&var*&med*type*source/printmiss misstext='0';
	format pat_co county.;

run;

data &med._d_&var;
set &med._d_&var;
drug_grp = &var3;
run; 

proc tabulate data = poison_all out = &med._p_&var2(drop=_type_ _page_ _table_) missing;
where &var2 = 1;
	class dischyear;
	class &var2;
	class los;
	class type;
	class source;
	class &med;
	class pat_co/preloadfmt;
	table dischyear*pat_co*&var2*&med*type*source/printmiss misstext='0';
	format pat_co county.;

run;

data &med._p_&var2;
set &med._p_&var2;
drug_grp = &var3;
run; 


%mend;
%med (Medicaid, alcohol, alcohol_od, 1);
%med (Medicaid, stimulant, stimulant_od, 2);
%med (Medicaid, opioid, opioid_od, 3);
%med (Medicaid, allsubstances, allsubstances_od, 4);




data medicaid_final;
set medicaid_d_alcohol medicaid_d_stimulant medicaid_d_opioid medicaid_d_allsubstances 
    medicaid_p_alcohol_od medicaid_p_stimulant_od medicaid_p_opioid_od medicaid_p_allsubstances_od;

	if source = "In Patient" then source = "Inpatient";

run;

data medicaid_final2;
set medicaid_final;
if n = . then n = 0;
if medicaid = . then medicaid = 0;
rename N = Count drug_grp = Drug pat_co = County Dischyear = Year;
format drug drug_grp.;
drop alcohol alcohol_od stimulant stimulant_od opioid opioid_od allsubstances allsubstances_od;
run;


proc delete data = medicaid_d_alcohol medicaid_d_stimulant medicaid_d_opioid medicaid_d_allsubstances 
				   medicaid_p_alcohol_od medicaid_p_stimulant_od medicaid_p_opioid_od medicaid_p_allsubstances_od
				   medicaid_final ;
run;


/*----------------------------------------------END OF MEDICARE/MEDICAID----------------------------------------------*/

data all;
set death_final2 dependence_final2 poison_final2;
rename N = Count drug = Drug;
run;

/*

libname sb "S:\ANALYTICS\PUBLICATIONS\DASHBOARDS\Published\Substance Use\SAS Export";


data sb.all;
set all;

run;

data sb.medicaid_final2;
set medicaid_final2;
run;

data sb.los_final;
set los_final;
run;



options compress = NO;


data sb.all;
set sb.all;
rename N = Count;
run;

data sb.medicaid_final2;
set sb.medicaid_final2;
rename dischyear = Year pat_co = County drug_grp = Drug N = Count;
run;

data sb.los_final;
set sb.los_final;
rename dischyear = Year pat_co = County drug_grp = Drug los = Days N = Count;
run;
*/


%let excel = Substance Use Dashboard Data.xlsx;
%macro excel (dataset, tabName, location, var);
FILENAME XLTARGET DDE "EXCEL|S:\ANALYTICS\PUBLICATIONS\DASHBOARDS\Published\Substance Use\[&excel]&tabName.!&location";
data _null_;
set &dataset;
file XLTARGET dlm='09'x notab;;
put &var;
run;
%mend;
/*Death Data Tables*/
%excel (all, Data, R2C1:R200000C9, Year County Drug Demographic Type Source count Population );
%excel (medicaid_final2, Medicaid, R2C1:R10000C7, year county drug Type Source medicaid count  );
%excel (los_final, Length of Stay, R2C1:R400000C7, year county drug Type Source days count  );

ods select all;









