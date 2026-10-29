# Heart Disease Risk Factors: SQL, Power BI and Machine Learning

An end-to-end analysis of 1,000 patient records: cleaning and exploring the data in MySQL, visualizing disease rates in Power BI, and comparing two machine learning models (logistic regression and random forest) to find which factors predict heart disease.

<img width="1820" height="1088" alt="HeartDiseaseDashboard" src="https://github.com/user-attachments/assets/9a26b553-201c-4ca5-810d-9e460c5e3cfd" />

## Summary of findings

- **29.4% of the 1,000 patients have heart disease** (294 patients).
- **Disease rates climb steadily with BMI and blood pressure.** From 12.3% for underweight patients to 45.5% for obese patients, and from 11.7% for normal blood pressure to 48.3% for stage 2 hypertension.
- **Smoking and family history compound.** Among current smokers, the disease rate is 39.6% without a family history and 59.5% with one. For former and never smokers, family history barely changes the rate.
- **Risk rises sharply with age and is higher for men.** In the 60+ bracket, 57.7% of men have heart disease vs. 38.0% of women.
- **Cardiac fitness is the strongest signal.** Patients with heart disease reached an average maximum heart rate of 143.8 bpm, compared with 174.1 bpm for patients without it, and it was the largest effect in the logistic regression model.
- **Logistic regression was the best model**, with 91.5% test accuracy (the baseline of always predicting "no disease" is 70.5%) and 81% recall on disease cases.

## Data and tools

- **Data:** 1,000 patients and 27 original columns covering demographics, vitals, lab values, lifestyle and wearable-device measures, plus the target `has_heart_disease`. No missing values or duplicate patients. Source: [Kaggle].
- **MySQL** for cleaning, feature engineering and grouped disease-rate queries.
- **Power BI** for the dashboard.
- **Python** (pandas, scikit-learn, matplotlib) for the models.

## Questions

1. Is the data internally consistent?
2. Which patient groups have the highest disease rates (by BMI, blood pressure, smoking, family history, sex and age)?
3. Can a model predict heart disease from these measurements, and how well?
4. Which factors matter most once they are considered together?

## Data cleaning and feature engineering

**Cross-field check.** HDL and LDL cholesterol are parts of total cholesterol, so their sum should never exceed it. 14 patients broke this rule, by 1 to 12 points (median 2.5). That looks like lab rounding and measurement noise rather than data entry errors, so every row was kept and the 14 patients were marked in a `chol_inconsistency_flag` column.

**Engineered categories.** Three bins were built from numeric columns, each previewed with a `SELECT` before being applied with an `UPDATE`:

- **BMI category:** underweight, healthy, overweight or obese, using standard weight bands.
- **Blood pressure category:** normal, elevated, stage 1 hypertension or stage 2 hypertension.
- **Age bracket:** Under 30, 30-44, 45-59 and 60+, for grouping and for the dashboard filter. An early version of this bin lumped the 38 patients under 30 into 60+, which understated the 60+ disease rate; the logic was corrected and the queries rerun.

## Exploration

Each group's disease rate is `SUM(has_heart_disease) * 100.0 / COUNT(*)`.

| Group | Disease rate | Patients |
|---|---|---|
| Underweight | 12.3% | 65 |
| Healthy weight | 21.0% | 395 |
| Overweight | 35.1% | 408 |
| Obese | 45.5% | 132 |
| Normal blood pressure | 11.7% | 222 |
| Elevated | 29.7% | 145 |
| Stage 1 hypertension | 31.6% | 484 |
| Stage 2 hypertension | 48.3% | 149 |

| Smoker status | No family history | Family history |
|---|---|---|
| Never | 25.3% | 27.7% |
| Former | 26.6% | 27.3% |
| Current | 39.6% | 59.5% (42 patients) |

The two-way grouping shows that the factors combine in a specific way: family history matters mainly when smoking is active.

Disease rate also climbs steeply with age, and faster for men (number of patients in parentheses):

| Age bracket | Female | Male |
|---|---|---|
| Under 30 | 0.0% (12) | 3.8% (26) |
| 30-44 | 10.8% (93) | 13.5% (96) |
| 45-59 | 16.2% (210) | 30.8% (211) |
| 60+ | 38.0% (163) | 57.7% (189) |

## Machine learning

**Setup.** The target is `has_heart_disease`. Identifiers, the cleaning flag and the three binned columns were dropped (the binned columns duplicate raw numeric columns the model can use directly). Sex and the true/false columns were converted to 0/1, and chest pain type and smoker status were one-hot encoded because they have no natural order. The data was split 80/20 (800 training and 200 test patients), stratified so both sets keep the roughly 70/30 class balance. Features were scaled for logistic regression only, with the scaler fit on the training data alone to avoid leakage.

**Results on the 200 held-out patients (59 with heart disease):**

| Model | Accuracy | Precision | Recall | F1 | Disease cases caught |
|---|---|---|---|---|---|
| Logistic regression | 91.5% | 0.89 | 0.81 | 0.85 | 48 of 59 |
| Random forest (default) | 89.5% | 0.87 | 0.76 | 0.81 | 45 of 59 |
| Random forest (tuned) | 90.0% | 0.90 | 0.75 | 0.81 | 44 of 59 |

Precision, recall and F1 are for the heart disease class. Recall is the number to watch, because a missed case (false negative) is worse than a false alarm.

**Overfitting.** The default random forest scored 100% accuracy on training data but 89.5% on test data. I tuned `max_depth` and `min_samples_leaf` with 5-fold cross-validation on the training set only, optimizing for recall. The tuned forest chose a depth of 10 and a minimum of 5 samples per leaf, which narrowed the train/test gap (95.1% vs. 90.0%), but it still did not beat logistic regression.

**Which factors matter most.** Because the features were scaled, each odds ratio below is the change in the odds of disease for a one-standard-deviation increase in that feature, holding the others constant.

| Factor | Odds ratio |
|---|---|
| Max heart rate achieved | 0.09 (a higher heart rate means much lower risk) |
| Exercise-induced angina | 2.70 |
| ST depression | 2.11 |
| Age | 0.48 (counterintuitive, see below) |
| Family history | 1.54 |
| Male sex | 1.48 |
| Current smoker | 1.43 |
| HDL cholesterol | 0.71 (higher HDL lowers risk) |
| Total cholesterol | 1.38 |
| BMI | 1.37 |

These are the ten largest effects by absolute coefficient. Two variables behaved differently in the model than in single-variable comparisons. LDL cholesterol had a small effect (OR 1.11), and age had a *negative* coefficient once the other variables were included, which is counterintuitive. This is most likely multicollinearity: age correlates strongly with max heart rate (-0.74), and LDL with total cholesterol (0.85), so the model splits or reassigns their effects between the correlated variables. Coefficients of correlated features should not be read in isolation. That the simple linear model beat the random forest suggests the relationships are close to linear.

## Limitations

- **Associations, not causes.** This is an observational analysis and says nothing about what would happen if a patient changed one factor.
- **Small test set.** The models were compared on one 200-patient split, and the gaps between them are a few patients (48 vs. 44 disease cases caught). Treat the ranking as indicative, not definitive. All three models were also scored on the same test set, so a more rigorous comparison would use cross-validation across all models.
- **Not a diagnostic tool.** This is a learning project, and the model should not be used for clinical decisions.
- **Simplified categories.** BMI, blood pressure and age groups use fixed cutoffs.
- **Small subgroups.** Some groups are small, for example the 42 current smokers with a family history, so their rates are less precise.
- **Dataset provenance.** [Data is synthetically created as was downloaded from Kaggle]

## Repository contents

| File | Description |
|---|---|
| `heart_disease_factors_analysis.sql` | MySQL cleaning, feature engineering and exploration, with comments |
| `heart_disease_risk_updated.csv` | The cleaned dataset exported from MySQL |
| `HeartDisease2026_ML.ipynb` | Notebook with both models, tuning and the feature analysis |

## Skills demonstrated

Data validation, feature engineering with `CASE`, grouped aggregation, Power BI visuals and filters, train/test splitting, leakage-aware preprocessing, logistic regression and random forest models, overfitting diagnosis, cross-validated hyperparameter tuning, precision/recall evaluation, and odds-ratio interpretation.
