const MARKETING_FORMS = ['campaign-flagship', 'campaign-comparison', 'campaign-short', 'campaign-outreach', 'marketing-cutdown', 'social-clip', 'hero'];

export function isMarketingCut(job) {
  return job?.marketing === true || job?.kind === 'teaser' || MARKETING_FORMS.includes(job?.programForm);
}
