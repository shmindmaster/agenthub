const MARKETING_FORMS = ['campaign-flagship', 'campaign-comparison', 'campaign-short', 'campaign-outreach', 'marketing-cutdown', 'social-clip', 'hero'];

export function isMarketingCut(job) {
  return job?.marketing === true || job?.filmType === 'product-marketing'
    || job?.kind === 'teaser' || MARKETING_FORMS.includes(job?.programForm);
}
