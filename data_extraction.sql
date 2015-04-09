declare @study_year int, @study_max_date nvarchar(10), @study_min_date nvarchar(10)

set @study_year=2014
set @study_max_date=cast((@study_year+1) as nvarchar)  + '-01-01'
set @study_min_date=cast((@study_year) as nvarchar)  + '-01-01'

--compute patient list and demographics variabls
if OBJECT_ID(N'demo_vars', 'U') is not null
begin
	drop table demo_vars
end

select Patient.Patient_ID, Sex, BirthYear, ResidencePostalCode PostalCode, DeceasedYear, Provider_ID
into demo_vars
from Patient, PatientDemographic, PatientProvider where 
Patient.Patient_ID=PatientDemographic.Patient_ID
and Patient.Patient_ID=PatientProvider.Patient_ID
and @study_year-BirthYear>=18

--compute encounter variables
if OBJECT_ID(N'en_vars', 'U') is not null
begin
	drop table en_vars
end

select Patient_ID, count(distinct Encounter_ID) encounter_count, count(distinct DM_Encounter_ID) dm_encounter_count
into en_vars
from 
(
select EncounterDiagnosis.Patient_ID, Encounter_ID,
iif (left(DiagnosisCode_calc,3)='250', Encounter_ID, Null) DM_Encounter_ID
from EncounterDiagnosis, demo_vars
where EncounterDiagnosis.Patient_ID=demo_vars.Patient_ID
and DateCreated>=@study_min_date
and DateCreated<@study_max_date
) en_data
group by Patient_ID

--compute lab variabls
if OBJECT_ID(N'lab_vars', 'U') is not null
begin
	drop table lab_vars
end

select Patient_ID,
count(hba1c_count) hba1c_count, cast(avg(hba1c_value) as numeric(5,2)) hba1c_value,
count(fbs_count) fbs_count, cast(avg(fbs_value) as numeric(5,2)) fbs_value,
count(lipid_count) lipid_count, 
cast(avg(tc_value) as numeric(5,2)) tc_value, cast(avg(ldl_value) as numeric(5,2)) ldl_value, cast(avg(hdl_value) as numeric(5,2)) hdl_value
into lab_vars
from 
(
select lab.Patient_ID, 
iif (name_calc='HBA1C', 1, null) hba1c_count,
iif (name_calc='HBA1C', cast(TestResult_calc as numeric(5,2)), null) hba1c_value,
iif (name_calc='FASTING GLUCOSE', 1, null) fbs_count,
iif (name_calc='FASTING GLUCOSE', cast(TestResult_calc as numeric(5,2)), null) fbs_value,
iif (name_calc in ('TOTAL CHOLESTEROL', 'LDL', 'HDL', 'TRIGLYCERIDES'), 1, null) lipid_count,
iif (name_calc='TOTAL CHOLESTEROL', cast(TestResult_calc as numeric(5,2)), null) tc_value,
iif (name_calc='LDL', cast(TestResult_calc as numeric(5,2)), null) ldl_value,
iif (name_calc='HDL', cast(TestResult_calc as numeric(5,2)), null) hdl_value
from lab, demo_vars
where lab.Patient_ID=demo_vars.Patient_ID
and DateCreated>=@study_min_date
and DateCreated<@study_max_date
) lab_data
group by Patient_ID

--compute condition variabls
if OBJECT_ID(N'condition_vars', 'U') is not null
begin
	drop table condition_vars
end

select Patient_ID,
max(diabetes) diabetes,
max(hypertension) hypertension,
max(hyperlipidemia) hyperlipidemia,
max(ihd) ihd,
max(cerebrovascular_disease) cerebrovascular_disease
into condition_vars
from 
(
select condition.Patient_ID, 
case when DiagnosisCode_calc in ('Diabetes Mellitus') then 1 else 0 end diabetes,
case when DiagnosisCode_calc in ('Hypertension') then 1 else 0 end hypertension,
case when left(DiagnosisCode_calc,3) in ('272') and DiagnosisCode_calc not in ('272.5','272.6','272.7','272.8','272.9')  then 1 else 0 end hyperlipidemia,
case when left(DiagnosisCode_calc,3) between '410' and '414' or DiagnosisCode_calc='429.2' then 1 else 0 end ihd,
case when left(DiagnosisCode_calc,3) between '436' and '437' then 1 else 0 end cerebrovascular_disease
from 
(
select patient_id, DiagnosisCode_calc, DateCreated from EncounterDiagnosis
union
select patient_id, DiagnosisCode_calc, DateCreated from HealthCondition
union
select patient_id, Disease as DiagnosisCode_calc, DateOfOnset as DateCreated from DiseaseCase
) as condition
, demo_vars
where condition.Patient_ID=demo_vars.Patient_ID
and DateCreated<@study_max_date
) condition_data
group by Patient_ID

--compute medication variabls
if OBJECT_ID(N'med_vars', 'U') is not null
begin
	drop table med_vars
end

select Patient_ID,
max(insulin) insulin,
max(metformin) metformin,
max(sulfonylurea) sulfonylurea,
max(other_oral_hypoglycemic) other_oral_hypoglycemic 
into med_vars
from 
(
select med.Patient_ID, 
case when (LEFT(Code_calc,4) IN ('A10A'))
	 AND startdate<@study_max_date and stopdate>@study_min_date
	 then 1 else 0 end insulin,
case when (LEFT(Code_calc,5) IN ('A10BA') OR LEFT(Code_calc,7) IN ('A10BD02','A10BD03','A10BD05','A10BD07','A10BD08'))
	 AND startdate<@study_max_date and stopdate>@study_min_date
	 then 1 else 0 end metformin,
case when (LEFT(Code_calc,5) IN ('A10BB', 'A10BC') OR LEFT(Code_calc,7) IN ('A10BD01','A10BD02','A10BD04','A10BD06'))
	 AND startdate<@study_max_date and stopdate>@study_min_date
	 then 1 else 0 end sulfonylurea,
case when (LEFT(Code_calc,5) IN ('A10BF', 'A10BG', 'A10BH') OR LEFT(Code_calc,7) IN ('A10BD03','A10BD04','A10BD05','A10BD06', 'A10BD07', 'A10BD08', 'A10BD09'))
	 AND startdate<@study_max_date and stopdate>@study_min_date
	 then 1 else 0 end other_oral_hypoglycemic
from
(
select patient_id, Code_calc, startdate, iif(stopdate is null, dateadd(y, 1, startdate), stopdate) stopdate
from Medication
where code_calc is not null and startdate is not null
) med, demo_vars
where med.Patient_ID=demo_vars.Patient_ID
) med_data
group by Patient_ID

--compute exam variabls
if OBJECT_ID(N'exam_vars', 'U') is not null
begin
	drop table exam_vars
end
select Patient_ID,
avg(sbp) sbp,
avg(dbp) dbp,
avg(bodyweight) bodyweight 
into exam_vars
from 
(
select exam.Patient_ID, 
case when exam1='sBP (mmHg)' then cast(Result1_calc as numeric(5,2)) else null end sbp,
case when exam1='sBP (mmHg)' then cast(Result2_calc as numeric(5,2)) else null end dbp,
case when exam1='Weight (kg)' then cast(Result1_calc as numeric(5,2)) else null end bodyweight
from 
exam, demo_vars
where Exam.Patient_ID=demo_vars.Patient_ID
and DateCreated>=@study_min_date
and DateCreated<@study_max_date
) exam_data
group by Patient_ID

if OBJECT_ID(N'study_vars', 'U') is not null
begin
	drop table study_vars
end

select
demo_vars.*,
iif(en_vars.Patient_ID is null, 0, en_vars.encounter_count) as encounter_count,
iif(en_vars.Patient_ID is null, 0, en_vars.dm_encounter_count) as dm_encounter_count,
iif(lab_vars.Patient_ID is null, 0, lab_vars.hba1c_count) as hba1c_count,
hba1c_value,
iif(lab_vars.Patient_ID is null, 0, lab_vars.fbs_count) as fbs_count,
fbs_value,
iif(lab_vars.Patient_ID is null, 0, lab_vars.lipid_count) as lipid_count,
tc_value,
ldl_value,
hdl_value,
iif(condition_vars.Patient_ID is null, 0, condition_vars.diabetes) as diabetes,
iif(condition_vars.Patient_ID is null, 0, condition_vars.hypertension) as hypertension,
iif(condition_vars.Patient_ID is null, 0, condition_vars.hyperlipidemia) as hyperlipidemia,
iif(condition_vars.Patient_ID is null, 0, condition_vars.ihd) as ihd,
iif(condition_vars.Patient_ID is null, 0, condition_vars.cerebrovascular_disease) as cerebrovascular_disease,
sbp,
dbp,
bodyweight,
iif(med_vars.Patient_ID is null, 0, med_vars.insulin) as insulin,
iif(med_vars.Patient_ID is null, 0, med_vars.metformin) as metformin,
iif(med_vars.Patient_ID is null, 0, med_vars.sulfonylurea) as sulfonylurea,
iif(med_vars.Patient_ID is null, 0, med_vars.other_oral_hypoglycemic) as other_oral_hypoglycemic
into study_vars
from
demo_vars
left join en_vars on demo_vars.Patient_ID=en_vars.Patient_ID
left join lab_vars on demo_vars.Patient_ID=lab_vars.Patient_ID
left join condition_vars on demo_vars.Patient_ID=condition_vars.Patient_ID
left join exam_vars on demo_vars.Patient_ID=exam_vars.Patient_ID
left join med_vars on demo_vars.Patient_ID=med_vars.Patient_ID
where
@study_year-BirthYear>=18