# Generates synthetic e-commerce data, loads SQLite, runs RFM / cohort / churn / DQ SQL.
import numpy as np, pandas as pd, sqlite3
rng=np.random.default_rng(42); START=pd.Timestamp('2024-10-01'); NM=24; ASOF='2026-10-01'
prods=pd.DataFrame({'product_id':range(1,21),'category':np.repeat(['Beverages','Snacks','Personal Care','Home Care'],5),'price':rng.integers(20,200,20)})
pw=np.linspace(2,.5,20); pw/=pw.sum()
chan=['Organic','Paid Social','Email','Referral']; haz={'Organic':.06,'Paid Social':.12,'Email':.07,'Referral':.04}
cust=[];orders=[];items=[];oid=0
for m in range(NM):
    promo=(m==13)                                   # Nov-2025 Black Friday promo cohort
    n=420 if promo else int(rng.integers(90,130)*(1+m/24))
    for _ in range(n):
        cid=len(cust)+1
        c=rng.choice(chan,p=[.15,.65,.1,.1] if promo else [.35,.30,.20,.15])
        h=haz[c]+(.08 if promo else 0)
        sd=START+pd.DateOffset(months=m)+pd.Timedelta(days=int(rng.integers(0,28)))
        cust.append((cid,sd.date().isoformat(),c))
        for k in range(m,NM):
            if k==m: no=1
            else:
                if rng.random()<h: break
                no=rng.poisson(.5)
            for _ in range(no):
                oid+=1
                d=sd if k==m else START+pd.DateOffset(months=k)+pd.Timedelta(days=int(rng.integers(0,28)))
                orders.append((oid,cid,d.date().isoformat()))
                disc=.25 if (promo and k==m) else rng.choice([0,.05,.1],p=[.6,.25,.15])
                for p in rng.choice(20,int(rng.integers(1,5)),replace=False,p=pw):
                    items.append((oid,p+1,int(rng.integers(1,4)),round(prods.price[p]*(1-disc),2)))
db=sqlite3.connect(':memory:')
pd.DataFrame(cust,columns=['customer_id','signup_date','channel']).to_sql('customers',db,index=False)
pd.DataFrame(orders,columns=['order_id','customer_id','order_date']).to_sql('orders',db,index=False)
pd.DataFrame(items,columns=['order_id','product_id','qty','unit_price']).to_sql('items',db,index=False)
prods.to_sql('products',db,index=False)
q=lambda s:pd.read_sql(s,db)
OV="ov AS (SELECT o.order_id,o.customer_id,o.order_date,SUM(i.qty*i.unit_price) val,SUM(i.qty) units FROM orders o JOIN items i USING(order_id) GROUP BY 1,2,3)"
pd.set_option('display.width',200)
print('ROWS',q("SELECT (SELECT COUNT(*) FROM customers) c,(SELECT COUNT(*) FROM orders) o,(SELECT COUNT(*) FROM items) i").to_dict('records'))
print('KPI\n',q(f"WITH {OV} SELECT COUNT(DISTINCT customer_id) customers,COUNT(*) orders,ROUND(SUM(val)) revenue,ROUND(AVG(val),1) aov,ROUND(AVG(units),2) units_per_basket FROM ov"))
print('REPEAT\n',q("SELECT ROUND(100.0*SUM(n>=2)/COUNT(*),1) repeat_pct, ROUND(AVG(n),2) avg_orders FROM (SELECT customer_id,COUNT(*) n FROM orders GROUP BY 1)"))
RFM=f"""WITH {OV}, c AS (SELECT customer_id,CAST(julianday('{ASOF}')-julianday(MAX(order_date)) AS INT) recency,COUNT(*) freq,SUM(val) monetary FROM ov GROUP BY 1),
s AS (SELECT *,NTILE(5) OVER (ORDER BY recency DESC) r,CASE WHEN freq=1 THEN 1 WHEN freq=2 THEN 2 WHEN freq<=4 THEN 3 WHEN freq<=7 THEN 4 ELSE 5 END f,NTILE(5) OVER (ORDER BY monetary) m FROM c),
g AS (SELECT *,CASE WHEN r>=4 AND f>=4 THEN 'Champions' WHEN r>=3 AND f>=3 THEN 'Loyal' WHEN r>=4 AND f<=2 THEN 'New / Promising' WHEN r<=2 AND f>=3 THEN 'At Risk (was loyal)' WHEN r<=2 AND f<=2 THEN 'Hibernating / Lost' ELSE 'Need Attention' END segment FROM s)
SELECT segment,COUNT(*) customers,ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER(),1) cust_pct,ROUND(100.0*SUM(monetary)/SUM(SUM(monetary)) OVER(),1) rev_pct,ROUND(AVG(monetary)) avg_spend,ROUND(AVG(recency)) avg_recency,ROUND(AVG(freq),1) avg_orders FROM g GROUP BY 1 ORDER BY rev_pct DESC"""
print('RFM\n',q(RFM))
coh=q("""WITH a AS (SELECT DISTINCT customer_id,substr(order_date,1,7) ym FROM orders), f AS (SELECT customer_id,substr(MIN(order_date),1,7) cohort FROM orders GROUP BY 1)
SELECT cohort,(CAST(substr(ym,1,4) AS INT)*12+CAST(substr(ym,6,2) AS INT))-(CAST(substr(cohort,1,4) AS INT)*12+CAST(substr(cohort,6,2) AS INT)) mi,COUNT(*) active FROM a JOIN f USING(customer_id) GROUP BY 1,2""")
pv=coh.pivot(index='cohort',columns='mi',values='active'); ret=(pv.div(pv[0],axis=0)*100).round(1)
out=ret[[1,3,6,12]].copy(); out.insert(0,'size',pv[0].astype(int)); print('COHORT\n',out.to_string())
print('AVG RETENTION by month idx\n',ret[[1,2,3,6,9,12]].mean().round(1).to_dict())
print('CHANNEL\n',q(f"""WITH {OV}, c AS (SELECT customer_id,COUNT(*) n,SUM(val) rev,MAX(order_date) last,AVG(val) aov FROM ov GROUP BY 1)
SELECT cu.channel,COUNT(*) customers,ROUND(100.0*SUM(n>=2)/COUNT(*),1) repeat_pct,ROUND(100.0*SUM(julianday('{ASOF}')-julianday(last)>90)/COUNT(*),1) churn_pct,ROUND(AVG(aov),1) aov,ROUND(AVG(rev)) rev_per_cust FROM c JOIN customers cu USING(customer_id) GROUP BY 1 ORDER BY churn_pct DESC"""))
print('CHURN by cohort (90d inactive, cohorts older than 4 mo)\n',q(f"""SELECT substr(signup_date,1,7) cohort,COUNT(*) size,ROUND(100.0*SUM(julianday('{ASOF}')-julianday(l)>90)/COUNT(*),1) churn_pct FROM (SELECT cu.customer_id,cu.signup_date,MAX(o.order_date) l FROM customers cu JOIN orders o USING(customer_id) GROUP BY 1,2) WHERE signup_date<'2026-06-01' GROUP BY 1 ORDER BY churn_pct DESC LIMIT 5""").to_string())
print('PROMO vs OTHER cohorts: M3 retention', ret.loc['2025-11',3], 'vs median', ret[3].median().round(1))
print('DQ',q(f"""WITH {OV} SELECT (SELECT COUNT(*) FROM customers WHERE channel IS NULL OR signup_date IS NULL) null_cust,
(SELECT COUNT(*) FROM (SELECT customer_id,order_date,COUNT(*) n FROM orders GROUP BY 1,2 HAVING n>1)) same_day_multi_orders,
(SELECT COUNT(*) FROM items WHERE qty<=0 OR unit_price<=0) bad_items,
(SELECT COUNT(*) FROM orders WHERE customer_id NOT IN (SELECT customer_id FROM customers)) orphan_orders,
(SELECT COUNT(*) FROM orders o WHERE NOT EXISTS (SELECT 1 FROM items i WHERE i.order_id=o.order_id)) orders_no_items,
(SELECT COUNT(*) FROM ov,(SELECT AVG(val) a,AVG(val*val)-AVG(val)*AVG(val) v FROM ov) s WHERE val>a+3*sqrt(v)) outliers_3sd""").to_dict('records'))
