import http from 'k6/http'
import { sleep, group } from 'k6'
import { expect } from './lib/k6chaijs.js'
import { SharedArray } from 'k6/data'
import { Trend } from 'k6/metrics'

const HOST_URL = __ENV.HOST_URL || 'https://grants-ui.perf-test.cdp-int.defra.cloud'
const DURATION_SECONDS = __ENV.DURATION_SECONDS || 180
const RAMPUP_SECONDS = __ENV.RAMPUP_SECONDS || 30
const VU_COUNT = __ENV.VU_COUNT || 100
const P95_THRESHOLD_MS = __ENV.P95_THRESHOLD_MS || 3000

const durationCheckDetails = new Trend('duration_check_details')
const durationUpdateDetails = new Trend('duration_update_details')
const durationTasks = new Trend('duration_tasks')
const durationEligibilityLandRegistered = new Trend('duration_eligibility_land_registered')
const durationExitEligibilityLandRegistered = new Trend('duration_exit_eligibility_land_registered')
const durationEligibilityManagementControl = new Trend('duration_eligibility_management_control')
const durationEligibilityTenant = new Trend('duration_eligibility_tenant')
const durationEligibilityCountersignature = new Trend('duration_eligibility_countersignature')
const durationExitEligibilityCountersignature = new Trend('duration_exit_eligibility_countersignature')
const durationEligibilityTenantObligations = new Trend('duration_eligibility_tenant_obligations')
const durationExitEligibilityTenantObligations = new Trend('duration_exit_eligibility_tenant_obligations')
const durationEligibilityGrazingRights = new Trend('duration_eligibility_grazing_rights')
const durationEligibilityValidWmp = new Trend('duration_eligibility_valid_wmp')
const durationEligibilityHigherTier = new Trend('duration_eligibility_higher_tier')
const durationEligibilityWmpAgreement = new Trend('duration_eligibility_wmp_agreement')
const durationLandParcels = new Trend('duration_land_parcels')
const durationTotalAreaOfWoodland = new Trend('duration_total_area_of_woodland')
const durationCentreOfWoodland = new Trend('duration_centre_of_woodland')
const durationWhichForestryCommissionTeam = new Trend('duration_which_forestry_commission_team')
const durationSummary = new Trend('duration_summary')
const durationPotentialFunding = new Trend('duration_potential_funding')
const durationDeclaration = new Trend('duration_declaration')
const durationConfirmation = new Trend('duration_confirmation')

export const options = {
    scenarios: {
        journey: {
            executor: 'ramping-vus',
            startVUs: 1,
            stages: [
                { duration: `${RAMPUP_SECONDS}s`, target: VU_COUNT },
                { duration: `${DURATION_SECONDS - RAMPUP_SECONDS}s`, target: VU_COUNT }
            ],
            gracefulRampDown: '0s',
            gracefulStop: '10s'
        },
    },
    thresholds: {
        duration_check_details: [`p(95)<${P95_THRESHOLD_MS}`],
        duration_update_details: [`p(95)<${P95_THRESHOLD_MS}`],
        duration_tasks: [`p(95)<${P95_THRESHOLD_MS}`],
        duration_eligibility_land_registered: [`p(95)<${P95_THRESHOLD_MS}`],
        duration_exit_eligibility_land_registered: [`p(95)<${P95_THRESHOLD_MS}`],
        duration_eligibility_management_control: [`p(95)<${P95_THRESHOLD_MS}`],
        duration_eligibility_tenant: [`p(95)<${P95_THRESHOLD_MS}`],
        duration_eligibility_countersignature: [`p(95)<${P95_THRESHOLD_MS}`],
        duration_exit_eligibility_countersignature: [`p(95)<${P95_THRESHOLD_MS}`],
        duration_eligibility_tenant_obligations: [`p(95)<${P95_THRESHOLD_MS}`],
        duration_exit_eligibility_tenant_obligations: [`p(95)<${P95_THRESHOLD_MS}`],
        duration_eligibility_grazing_rights: [`p(95)<${P95_THRESHOLD_MS}`],
        duration_eligibility_valid_wmp: [`p(95)<${P95_THRESHOLD_MS}`],
        duration_eligibility_higher_tier: [`p(95)<${P95_THRESHOLD_MS}`],
        duration_eligibility_wmp_agreement: [`p(95)<${P95_THRESHOLD_MS}`],
        duration_land_parcels: [`p(95)<${P95_THRESHOLD_MS}`],
        duration_total_area_of_woodland: [`p(95)<${P95_THRESHOLD_MS}`],
        duration_centre_of_woodland: [`p(95)<${P95_THRESHOLD_MS}`],
        duration_which_forestry_commission_team: [`p(95)<${P95_THRESHOLD_MS}`],
        duration_summary: [`p(95)<${P95_THRESHOLD_MS}`],
        duration_potential_funding: [`p(95)<${P95_THRESHOLD_MS}`],
        duration_declaration: [`p(95)<${P95_THRESHOLD_MS}`],
        duration_confirmation: [`p(95)<${P95_THRESHOLD_MS}`],
        checks: ['rate==1'],
        http_req_failed: ['rate==0']
    }
}

const users = new SharedArray('users', function () {
    const data = open('./dal-users.csv').split('\n').slice(1) // Skip header
    return data.filter(line => line.trim()).map(line => line.trim())
})

export default function () {
    let response = null

    const params = { headers: { 'Sec-Fetch-Site': 'same-origin' } }

    const navigateTo = function (url) {
        response = http.get(url, params)
    }

    const clickLink = function (text) {
        response = response.clickLink({ selector: `a:contains('${text}')`, params })
    }

    const submitForm = function (fields) {
        response = response.submitForm({ formSelector: 'form', fields: fields, params })
    }

    const submitJourneyForm = function (fields) {
        sleep(3) // Mimic human interaction
        fields = fields ?? {}
        let crumb = response.html().find(`input[name='crumb']`).attr('value')
        fields['crumb'] = crumb
        submitForm(fields)
    }

    try {
        const crn = users[__VU % users.length]

        group('login-and-clear-state', () => {
            navigateTo(`${HOST_URL}/woodland`)
            submitForm({ crn: crn, password: 'x' })
            if (response.url.includes('/organisations')) {
                const sbiValue = response.html().find('#sbi').first().attr('value')
                submitForm({ sbi: sbiValue })
            }
            clickLink('Clear application state')
            navigateTo(`${HOST_URL}/woodland`)
        })

        // check-details: submit No → update-details page → Back → back to check-details → submit Yes
        group('check-details', () => {
            expect(response.url).to.include('check-details')
            durationCheckDetails.add(response.timings.duration)
            submitJourneyForm({ businessDetailsUpToDate: 'false' })
        })
        
        group('update-details', () => {
            expect(response.url).to.include('update-details')
            expect(response.body).to.include('Update your details')
            durationUpdateDetails.add(response.timings.duration)
            clickLink('Back')
        })

        group('check-details', () => {
            expect(response.url).to.include('check-details')
            durationCheckDetails.add(response.timings.duration)
            submitJourneyForm({ businessDetailsUpToDate: 'true' })
        })

        group('tasks', () => {
            expect(response.url).to.include('tasks')
            durationTasks.add(response.timings.duration)
            clickLink('Land registration')
        })

        // eligibility-land-registered: submit No → exit page → Back → submit Yes
        group('eligibility-land-registered', () => {
            expect(response.url).to.include('eligibility-land-registered')
            durationEligibilityLandRegistered.add(response.timings.duration)
            submitJourneyForm({ landRegisteredWithRpa: 'false' })
        })

        group('exit-eligibility-land-registered', () => {
            expect(response.url).to.include('exit-eligibility-land-registered')
            durationExitEligibilityLandRegistered.add(response.timings.duration)
            clickLink('Back')
        })

        group('eligibility-land-registered', () => {
            expect(response.url).to.include('eligibility-land-registered')
            durationEligibilityLandRegistered.add(response.timings.duration)
            submitJourneyForm({ landRegisteredWithRpa: 'true' })
        })

        group('eligibility-management-control', () => {
            expect(response.url).to.include('eligibility-management-control')
            durationEligibilityManagementControl.add(response.timings.duration)
            submitJourneyForm({ landManagementControl: 'false' })
        })

        // eligibility-countersignature: submit No → exit page → Back → submit Yes
        group('eligibility-countersignature', () => {
            expect(response.url).to.include('eligibility-countersignature')
            durationEligibilityCountersignature.add(response.timings.duration)
            submitJourneyForm({ counterSignature: 'false' })
        })

        group('exit-eligibility-countersignature', () => {
            expect(response.url).to.include('exit-eligibility-countersignature')
            durationExitEligibilityCountersignature.add(response.timings.duration)
            clickLink('Back')
        })

        group('eligibility-countersignature', () => {
            expect(response.url).to.include('eligibility-countersignature')
            durationEligibilityCountersignature.add(response.timings.duration)
            submitJourneyForm({ counterSignature: 'true' })
        })

        group('eligibility-tenant', () => {
            expect(response.url).to.include('eligibility-tenant')
            durationEligibilityTenant.add(response.timings.duration)
            submitJourneyForm({ publicBodyTenant: 'true' })
        })

        // eligibility-tenant-obligations: submit Yes → exit page → Back → submit No
        group('eligibility-tenant-obligations', () => {
            expect(response.url).to.include('eligibility-tenant-obligations')
            durationEligibilityTenantObligations.add(response.timings.duration)
            submitJourneyForm({ tenantObligations: 'true' })
        })

        group('exit-eligibility-tenant-obligations', () => {
            expect(response.url).to.include('exit-eligibility-tenant-obligations')
            durationExitEligibilityTenantObligations.add(response.timings.duration)
            clickLink('Back')
        })

        group('eligibility-tenant-obligations', () => {
            expect(response.url).to.include('eligibility-tenant-obligations')
            durationEligibilityTenantObligations.add(response.timings.duration)
            submitJourneyForm({ tenantObligations: 'false' })
        })

        group('eligibility-grazing-rights', () => {
            expect(response.url).to.include('eligibility-grazing-rights')
            durationEligibilityGrazingRights.add(response.timings.duration)
            submitJourneyForm({ landHasGrazingRights: 'true' })
        })

        group('eligibility-valid-wmp', () => {
            expect(response.url).to.include('eligibility-valid-wmp')
            durationEligibilityValidWmp.add(response.timings.duration)
            submitJourneyForm({ appLandHasExistingWmp: 'true' })
        })

        group('eligibility-wmp-agreement', () => {
            expect(response.url).to.include('eligibility-wmp-agreement')
            durationEligibilityWmpAgreement.add(response.timings.duration)
            submitJourneyForm({ existingWmps: 'WMP-12345, WMP-23456' })
        })

        group('eligibility-higher-tier', () => {
            expect(response.url).to.include('eligibility-higher-tier')
            durationEligibilityHigherTier.add(response.timings.duration)
            submitJourneyForm({ intendToApplyHigherTier: 'true' })
        })

        group('tasks', () => {
            expect(response.url).to.include('tasks')
            durationTasks.add(response.timings.duration)
            clickLink('Select land parcels')
        })

        group('land-parcels', () => {
            expect(response.url).to.include('land-parcels')
            durationLandParcels.add(response.timings.duration)
            const firstParcel = response.html().find('input[name="landParcels"]').first().attr('value')
            submitJourneyForm({ landParcels: firstParcel })
        })

        group('total-area-of-woodland', () => {
            expect(response.url).to.include('total-area-of-woodland')
            durationTotalAreaOfWoodland.add(response.timings.duration)
            submitJourneyForm({ hectaresTenOrOverYearsOld: '0.5', hectaresUnderTenYearsOld: '0' })
        })

        group('centre-of-woodland', () => {
            expect(response.url).to.include('centre-of-woodland')
            durationCentreOfWoodland.add(response.timings.duration)
            submitJourneyForm({ centreGridReference: 'SP 4178 2432' })
        })

        group('which-forestry-commission-team', () => {
            expect(response.url).to.include('which-forestry-commission-team')
            durationWhichForestryCommissionTeam.add(response.timings.duration)
            submitJourneyForm({ fcTeamCode: 'EAST_AND_EAST_MIDLANDS' })
        })

        group('tasks', () => {
            expect(response.url).to.include('tasks')
            durationTasks.add(response.timings.duration)
            clickLink('Check your answers')
        })

        group('summary', () => {
            expect(response.url).to.include('summary')
            durationSummary.add(response.timings.duration)
            submitJourneyForm()
        })

        group('potential-funding', () => {
            expect(response.url).to.include('potential-funding')
            durationPotentialFunding.add(response.timings.duration)
            submitJourneyForm()
        })

        group('declaration', () => {
            expect(response.url).to.include('declaration')
            durationDeclaration.add(response.timings.duration)
            submitJourneyForm()
        })

        group('confirmation', () => {
            expect(response.url).to.include('confirmation')
            durationConfirmation.add(response.timings.duration)
            expect(response.body).to.include('WMP-')
        })
    } catch (error) {
        console.error(`Error for URL: ${response?.url}, error: ${error.message}`)
        throw error
    }
}
