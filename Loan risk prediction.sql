-- =========================================================================
-- PROJECT TITLE: Loan Risk Prediction 
-- DATABASE: sara
-- TABLE: loans
-- =========================================================================

use sara;

drop table if exists loans; 

-- =========================================================================
-- 1. DATABASE SCHEMA CREATION
-- =========================================================================

create table Loans (
loan_id	           varchar(20) primary key,
age                int,
income             decimal (10,2),
loan_amount        decimal (10,2),
credit_score       smallint,
months_employed	   smallint,
num_credit_lines   tinyint,	
interest_rate	   decimal (5,2),
loan_term_months   int,
dti_ratio	       decimal (4,2),
education	       varchar(15),
employment_type	   varchar(20),
marital_status	   varchar(20),
has_mortgage	   varchar(8),
has_dependents	   varchar(8),
loan_purpose	   varchar(30),
has_cosigner	   varchar(8),
loan_default	   int,
employment_flag    varchar(5)
);

-- =========================================================================
-- 2. EXPLORATORY DATA ANALYSIS & PORTFOLIO OVERVIEW
-- =========================================================================

select * from loans
limit 5;

select count(*) from loans; -- total loans

select sum(loan_amount) as total_loan_amount -- total loan amount
from loans;

select loan_purpose, 
rank() over (order by count(*) desc) as purpose_of_loan 
from loans
group by loan_purpose 
order by count(*) desc;

with education_type as (
select  education, count(*) as most_prefers,  -- education type
round (count(*)*100/sum(count(*)) over(),2) as total_percent,
row_number () over (order by count(*) desc) as order_with_edu
from loans
group by education
order by count(*) desc
),
employment as (
select employment_type, total_count, total_percent, order_with_emp 
 from (
select employment_type, count(*) as total_count,
round(count(*)*100/sum(count(*))over(),2) as total_percent,
row_number () over (order by count(*) desc) as order_with_emp
from loans 
group by employment_type
) t
order by total_percent desc
) select e.education, e.most_prefers, e.total_percent as edu_percent, emp.employment_type,
emp.total_count, emp.total_percent as emp_percent 
from education_type e
join employment emp on e.order_with_edu = emp.order_with_emp;

select loan_default, sum(loan_amount) as total_loan_amt, -- 1 = defaulted, 0 = did not default
round(sum(loan_amount)*100/(select sum(loan_amount) from loans),2) as percent
from loans
group by loan_default;

-- =========================================================================
-- 3. DATA INTEGRITY & STATISTICAL SUMMARY CHECKS
-- =========================================================================

select * from loans
where loan_amount is null; 

select loan_id, count(*) as duplicate_loans 
from loans
group by loan_id
having count(*) > 1;

select 'age', min(age) as Min_val, max(age) as Max_val from loans 
union all 
select 'credit_score', min(credit_score), max(credit_score) from loans 
union all 
select 'dti_ratio', min(dti_ratio), max(dti_ratio) from loans
union all 
select 'interest_rate', min(interest_rate), max(interest_rate) from loans;

-- =========================================================================
-- ANALYTICAL QUERIES & INSIGHTS
-- =========================================================================

-- Part 1: How big is the problem?

--  Q1. What is the overall default rate, how many loans defaulted, and how much loan amount is at risk (the total loan_amount of defaulted loans, and its share of all lending)?

select count(*) as total_loans, sum(loan_default) as defaulted_loans,
round(avg(loan_default) * 100, 2) as default_rate,
sum(case when loan_default = 1 then loan_amount else 0 end) as amount_at_risk,
round(sum(case when loan_default = 1 then loan_amount else 0 end) * 100 / sum(loan_amount), 2) as pct_of_amount
from loans;

-- Part 2: Which borrowers and loans are riskier?

-- Q2. Which loan_purpose has the highest default rate, and which the lowest?

with highest_default_rate as 
(
select loan_purpose, total_default, loan_default, 
round(total_default*100/sum(total_default) over (partition by loan_purpose),2) as default_rate 
from (
select loan_purpose, count(loan_default) as total_default, loan_default 
from loans
group by loan_purpose, loan_default
order by count(loan_default) desc
) t 
) select loan_purpose, total_default, loan_default, default_rate 
from highest_default_rate
where loan_default = 1
order by default_rate desc;

-- Q3. How does the default rate differ by employment_type?

with employment_default as 
(
select employment_type, loan_default, total_default,
round (total_default*100/sum(total_default) over(partition by employment_type),2) as default_rate
from (
select employment_type, loan_default, count(*) as total_default 
from loans
group by employment_type, loan_default
) t
) select employment_type, loan_default, total_default, default_rate
from employment_default 
where loan_default = 1
order by default_rate desc;

-- Q4. Create credit score bands with CASE WHEN (Poor under 580, Fair 580 to 669, Good 670 to 739, Very good 740 to 799, Excellent 800 and above). Does the default rate fall as the score rises?

select  case 
when credit_score < 580 then 'Poor'
when credit_score between 580 and 669 then 'Fair'
when credit_score between 670 and 739 then 'Good'
when credit_score between 740 and 799 then 'Very Good'
else 'Excellent'
end as score_band,
count(credit_score) as loan,
round(avg(loan_default)*100,2) as default_rate
from loans
group by score_band
order by score_band;


-- Q5. Create age bands (18 to 29, 30 to 44, 45 to 59, 60 and above). Which band is riskiest?

select case 
when age < 30 then '18-29'
when age < 45 then '30-44'
when age < 60 then '45-59'
else '60+' end as age_band,
count(*) as loans,
sum(loan_default) as defaulted_loans,
round(avg(loan_default) * 100, 2) as default_rate
from loans
group by age_band
order by default_rate desc;

-- Q6. Create interest rate bands (up to 8, above 8 to 14, above 14 to 20, above 20). Do higher rates go with more defaults?

select case 
when interest_rate <= 8  then '1. up to 8'
when interest_rate <= 14 then '2. above 8 to 14'
when interest_rate <= 20 then '3. above 14 to 20'
else '4. above 20' end as rate_band,
count(*) as loans,
sum(loan_default) as defaulted_loans,
round(avg(loan_default) * 100, 2) as default_rate
from loans
group by rate_band
order by rate_band;

-- Q7. Create DTI bands (Low up to 0.30, Medium up to 0.50, High up to 0.70, Very high above 0.70). Does a heavier debt burden raise the default rate?

select case 
when dti_ratio <= 0.30 then 'Low'
when dti_ratio <= 0.50 then 'Medium'
when dti_ratio <= 0.70 then 'High'
else 'Very High'
end as dti_band,
count(*) as loan,
sum(loan_default) as defaulted_loans,
round (avg(loan_default)*100,2) as default_rate
from loans 
group by dti_band 
order by default_rate desc;

-- Part 3: Risk Factors & Predictive Cohorts

-- Q8. Does a co-signer help? Compare the default rate with and without a co-signer, overall and within each loan purpose. Does the effect hold in every purpose?

select loan_purpose, has_cosigner, count(*) as loans,
round(avg(loan_default)* 100, 2) as default_rate
from loans
group by loan_purpose, has_cosigner
order by loan_purpose, has_cosigner;

-- Q9. For each loan purpose, which employment_type has the highest default rate? Is it the same in every purpose? 

with default_rate as (
select loan_purpose, employment_type,
count(*) as loans,
sum(loan_default) as defaulted_loans,
round(avg(loan_default) * 100, 2) as default_rate,
rank() over (partition by loan_purpose order by avg(loan_default) desc) as rnk
from loans
group by loan_purpose, employment_type
)
select loan_purpose, employment_type, loans, defaulted_loans, default_rate
from default_rate
where rnk = 1
order by loan_purpose asc;

-- Q10. predicting default with credit score

with credit_band as 
(
select case 
when credit_score < 580 then 'Risky(below 580)'
when credit_score < 700 then 'Good(580-700)'
else 'Very Good(above 700)' 
end as credit_band,
count(*) as loans,
sum(loan_default) as default_loans,
round (avg(loan_default)*100,2) as default_rate
from loans
group by credit_band
) 
select credit_band, loans, default_loans, default_rate
from credit_band
order by default_rate desc;

--  